import Observation
import Foundation
import PokerBot
import PokerCore
import PokerSession

@MainActor @Observable
public final class CashTableCoordinator {
    public private(set) var state: TableViewState
    package private(set) var frozenSettings: BotSettings?

    private let store: LocalPokerStore
    private let humanSeat: SeatID
    private let seatProfiles: [TableSeatProfile]
    private let dependencies: TableRuntimeDependencies
    private var currentHandID: HandID?
    private var stateVersion = 0
    private nonisolated let countdownTask = CountdownTaskBox()

    public init(
        store: LocalPokerStore,
        humanSeat: SeatID,
        seatProfiles: [TableSeatProfile],
        dependencies: TableRuntimeDependencies
    ) throws {
        guard let session = store.cashSession else {
            throw PokerCoordinatorError.missingObservation
        }
        let profileBySeat = try CashTableProjection.validatedProfiles(
            seatProfiles,
            matching: session.seats.map(\.id),
            humanSeat: humanSeat
        )
        guard session.humanSeat == humanSeat else {
            throw PokerCoordinatorError.missingObservation
        }

        let initialSeats = try session.seats.sorted { $0.id < $1.id }.map { seat in
            guard let profile = profileBySeat[seat.id] else {
                throw PokerCoordinatorError.missingObservation
            }
            return TableSeatState(
                id: seat.id,
                displayName: profile.displayName,
                stack: seat.stack,
                committedThisStreet: try Chips(0),
                hasFolded: seat.hasFolded,
                isAllIn: seat.isAllIn,
                isDealer: seat.id == session.dealer,
                isCurrentActor: false,
                cards: []
            )
        }
        let initialState = TableViewState(
            handID: nil,
            stateVersion: 0,
            phase: .awaitingNextHand,
            seats: initialSeats,
            communityCards: [],
            pot: try Chips(0),
            controls: nil,
            secondsRemaining: nil,
            winners: [],
            errorMessage: nil,
            animation: nil
        )

        self.store = store
        self.humanSeat = humanSeat
        self.seatProfiles = seatProfiles
        self.dependencies = dependencies
        state = initialState
    }

    deinit {
        countdownTask.cancel()
    }

    public func startHand(settings: BotSettings) async throws {
        guard store.cashSession?.phase == .readyForHand else {
            throw PokerCoordinatorError.invalidPhase
        }
        frozenSettings = settings
        try refillBustedBotsToOneHundredBigBlinds()

        let handID = try dependencies.nextHandID()
        let transition = try store.startHand(
            id: handID,
            seed: dependencies.nextSeed()
        )
        currentHandID = handID
        incrementStateVersion()
        try await present(transition)
        try refreshProjection()
        await scheduleCurrentActorIfReady()
    }

    public func send(_ intent: TableIntent) async throws {
        guard state.phase != .suspended else {
            throw PokerCoordinatorError.suspended
        }
        guard let observation = try store.humanObservation(),
              observation.currentActor == humanSeat,
              let legalActions = observation.legalActions
        else {
            throw PokerCoordinatorError.illegalIntent
        }
        let action = try CashTableActionPipeline.action(
            for: intent,
            legalActions: legalActions
        )
        try await applyHumanAction(action)
    }

    public func suspend() {
        cancelCountdown()
        incrementStateVersion()
        state = replacingState(phase: .suspended, secondsRemaining: nil)
    }

    private func refillBustedBotsToOneHundredBigBlinds() throws {
        guard let config = store.activeCashConfig,
              let session = store.cashSession
        else {
            throw PokerCoordinatorError.chipArithmeticOverflow
        }
        let target = try Self.oneHundredBigBlindBotTarget(for: config.bigBlind)

        for seat in session.seats where seat.id != humanSeat && seat.stack.rawValue == 0 {
            try store.refillBotSeat(seat.id, to: target)
        }
    }

    private func incrementStateVersion() {
        let (next, overflow) = stateVersion.addingReportingOverflow(1)
        stateVersion = overflow ? Int.max : next
    }

    private func present(_ transition: GameTransition) async throws {
        for event in transition.events {
            guard let animation = animation(for: event) else { continue }
            try refreshProjection(animation: animation)
            try await dependencies.sleep(.zero)
        }
    }

    private func refreshProjection(
        animation: TableAnimationEvent? = nil,
        secondsRemaining: Int? = nil
    ) throws {
        guard let currentHandID else {
            throw PokerCoordinatorError.missingObservation
        }
        state = try CashTableProjection.make(
            store: store,
            handID: currentHandID,
            stateVersion: stateVersion,
            humanSeat: humanSeat,
            seatProfiles: seatProfiles,
            animation: animation,
            secondsRemaining: secondsRemaining
        )
    }

    private func animation(for event: PublicGameEvent) -> TableAnimationEvent? {
        switch event {
        case let .blindPosted(seat, amount):
            return .postBlind(seat: seat, amount: amount)
        case let .holeCardsDealt(seat):
            return .dealHoleCard(seat: seat, card: .faceDown)
        case let .actionApplied(seat, action):
            return .showAction(seat: seat, action: action)
        default:
            return nil
        }
    }

    private func scheduleCurrentActorIfReady() async {
        cancelCountdown()
        guard let handID = currentHandID,
              store.cashSession?.phase == .handInProgress,
              store.cashSession?.currentActor == humanSeat
        else { return }

        let version = stateVersion
        do {
            try refreshProjection(secondsRemaining: 30)
        } catch {
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            for remaining in stride(from: 29, through: 0, by: -1) {
                do {
                    try await dependencies.sleep(.seconds(1))
                    try Task.checkCancellation()
                } catch {
                    return
                }
                guard currentHandID == handID,
                      stateVersion == version,
                      store.cashSession?.phase == .handInProgress,
                      store.cashSession?.currentActor == humanSeat
                else {
                    cancelCountdown()
                    return
                }
                if remaining > 0 {
                    try? refreshProjection(secondsRemaining: remaining)
                } else {
                    await performTimeout(handID: handID, stateVersion: version)
                }
            }
        }
        countdownTask.replace(with: task)
    }

    private func performTimeout(handID: HandID, stateVersion version: Int) async {
        guard currentHandID == handID,
              stateVersion == version,
              let observation = try? store.humanObservation(),
              observation.currentActor == humanSeat,
              let legalActions = observation.legalActions
        else { return }

        let action: PlayerAction?
        if legalActions.canCheck {
            action = .check
        } else if legalActions.canFold {
            action = .fold
        } else {
            action = nil
        }
        guard let action else { return }
        countdownTask.clear()
        try? await applyHumanAction(action)
    }

    private func applyHumanAction(_ action: PlayerAction) async throws {
        let transition = try store.apply(action, by: humanSeat)
        cancelCountdown()
        incrementStateVersion()
        try await present(transition)
        try refreshProjection()
        try await advanceCompletedRounds()
        await scheduleCurrentActorIfReady()
    }

    private func advanceCompletedRounds() async throws {
        while store.cashSession?.phase == .handInProgress,
              store.cashSession?.currentActor == nil {
            let transition = try store.advanceIfRoundComplete()
            incrementStateVersion()
            try await present(transition)
            try refreshProjection()
        }
    }

    private func cancelCountdown() {
        countdownTask.cancel()
    }

    private func replacingState(
        phase: TableFlowPhase? = nil,
        secondsRemaining: Int?
    ) -> TableViewState {
        TableViewState(
            handID: state.handID,
            stateVersion: stateVersion,
            phase: phase ?? state.phase,
            seats: state.seats,
            communityCards: state.communityCards,
            pot: state.pot,
            controls: state.controls,
            secondsRemaining: secondsRemaining,
            winners: state.winners,
            errorMessage: state.errorMessage,
            animation: state.animation
        )
    }

    nonisolated package static func oneHundredBigBlindBotTarget(
        for bigBlind: Chips
    ) throws -> Chips {
        let (rawTarget, overflow) = bigBlind.rawValue.multipliedReportingOverflow(by: 100)
        guard !overflow, let target = Chips(rawValue: rawTarget) else {
            throw PokerCoordinatorError.chipArithmeticOverflow
        }
        return target
    }
}

private final class CountdownTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func replace(with newTask: Task<Void, Never>?) {
        let oldTask = lock.withLock {
            let oldTask = task
            task = newTask
            return oldTask
        }
        oldTask?.cancel()
    }

    func cancel() {
        replace(with: nil)
    }

    func clear() {
        lock.withLock { task = nil }
    }
}
