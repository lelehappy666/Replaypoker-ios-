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
    private let botService: any BotDecisionServing
    private var currentHandID: HandID?
    private var stateVersion = 0
    private nonisolated let countdownTask = CountdownTaskBox()
    private nonisolated let botTask = BotTaskBox()

    public convenience init(
        store: LocalPokerStore,
        humanSeat: SeatID,
        seatProfiles: [TableSeatProfile],
        dependencies: TableRuntimeDependencies
    ) throws {
        try self.init(
            store: store,
            humanSeat: humanSeat,
            seatProfiles: seatProfiles,
            dependencies: dependencies,
            botService: BotDecisionService()
        )
    }

    package init(
        store: LocalPokerStore,
        humanSeat: SeatID,
        seatProfiles: [TableSeatProfile],
        dependencies: TableRuntimeDependencies,
        botService: any BotDecisionServing
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
        self.botService = botService
        state = initialState
    }

    deinit {
        countdownTask.cancel()
        botTask.cancel()
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
        let operationVersion = stateVersion
        guard try await present(
            transition,
            guardedBy: operationVersion
        ) else { return }
        guard isCurrentOperation(operationVersion) else { return }
        try refreshProjection()
        guard isCurrentOperation(operationVersion) else { return }
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
        cancelBotDecision()
        incrementStateVersion()
        state = replacingState(phase: .suspended, secondsRemaining: nil)
    }

    package func runUntilHumanOrSettlement() async throws {
        while store.cashSession?.phase == .handInProgress,
              store.cashSession?.currentActor != humanSeat,
              state.phase != .suspended,
              state.errorMessage == nil {
            await Task.yield()
        }
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
              state.phase != .suspended,
              store.cashSession?.phase == .handInProgress,
              let actor = store.cashSession?.currentActor
        else { return }

        if actor != humanSeat {
            scheduleBotDecision(for: actor, handID: handID)
            return
        }

        let version = stateVersion
        do {
            try refreshProjection(secondsRemaining: 30)
        } catch {
            return
        }
        let sleep = dependencies.sleep
        let task = Task { @MainActor [weak self, sleep] in
            for remaining in stride(from: 29, through: 0, by: -1) {
                do {
                    try await sleep(.seconds(1))
                    try Task.checkCancellation()
                } catch {
                    return
                }
                guard let tick = self?.handleCountdownTick(
                    remaining: remaining,
                    handID: handID,
                    stateVersion: version
                ) else { return }
                switch tick {
                case .continueCountdown:
                    continue
                case .performTimeout:
                    await self?.performTimeout(handID: handID, stateVersion: version)
                    return
                case .stop:
                    return
                }
            }
        }
        countdownTask.replace(with: task)
    }

    private func scheduleBotDecision(for actor: SeatID, handID: HandID) {
        guard let session = store.cashSession,
              let config = store.activeCashConfig,
              let settings = frozenSettings,
              session.phase == .handInProgress,
              session.currentActor == actor,
              actor != humanSeat
        else { return }

        let player: PlayerObservation
        do {
            player = try Self.requireBotPlayerObservation(
                store.playerObservation(for: actor)
            )
        } catch {
            showBotError()
            return
        }

        let version = stateVersion
        let observation: BotObservation
        do {
            observation = try BotObservation(
                handID: handID.rawValue,
                stateVersion: version,
                config: config,
                observation: player
            )
        } catch {
            showBotError()
            return
        }
        let request = BotDecisionRequest(
            observation: observation,
            settings: settings,
            stableIdentity: "cash:\(session.id.rawValue):seat:\(actor.rawValue)",
            seed: dependencies.nextSeed(),
            history: nil
        )
        let service = botService
        let task = Task { @MainActor [weak self, service] in
            let decision = await service.decide(request)
            guard !Task.isCancelled else { return }
            await self?.handleBotDecision(
                decision,
                actor: actor,
                handID: handID,
                stateVersion: version
            )
        }
        botTask.replace(with: task)
    }

    private func handleBotDecision(
        _ decision: BotDecision?,
        actor: SeatID,
        handID: HandID,
        stateVersion version: Int
    ) async {
        guard currentHandID == handID,
              stateVersion == version,
              state.phase != .suspended,
              store.cashSession?.phase == .handInProgress,
              store.cashSession?.currentActor == actor
        else { return }

        let action: PlayerAction?
        if let decision {
            guard decision.handID == handID.rawValue,
                  decision.stateVersion == version
            else {
                showBotError()
                return
            }
            action = decision.action
        } else {
            let latest = try? store.playerObservation(for: actor)
            action = latest?.legalActions.flatMap(
                CashTableActionPipeline.fallbackAction
            )
        }
        guard let action else {
            showBotError()
            return
        }

        do {
            try await applyBotAction(
                action,
                actor: actor,
                handID: handID,
                stateVersion: version
            )
        } catch {
            showBotError()
        }
    }

    private func applyBotAction(
        _ action: PlayerAction,
        actor: SeatID,
        handID: HandID,
        stateVersion version: Int
    ) async throws {
        guard currentHandID == handID,
              stateVersion == version,
              store.cashSession?.currentActor == actor
        else { return }
        let transition = try store.apply(action, by: actor)
        botTask.clear()
        incrementStateVersion()
        var operationVersion = stateVersion
        guard try await present(transition, guardedBy: operationVersion) else { return }
        guard isCurrentOperation(operationVersion) else { return }
        try refreshProjection()
        guard try await advanceCompletedRounds(
            operationVersion: &operationVersion
        ) else { return }
        guard isCurrentOperation(operationVersion) else { return }
        await scheduleCurrentActorIfReady()
    }

    private func handleCountdownTick(
        remaining: Int,
        handID: HandID,
        stateVersion version: Int
    ) -> CountdownTickResult {
        guard currentHandID == handID,
              stateVersion == version,
              store.cashSession?.phase == .handInProgress,
              store.cashSession?.currentActor == humanSeat
        else {
            cancelCountdown()
            return .stop
        }
        if remaining > 0 {
            try? refreshProjection(secondsRemaining: remaining)
            return .continueCountdown
        }
        return .performTimeout
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
        var operationVersion = stateVersion
        guard try await present(transition, guardedBy: operationVersion) else { return }
        guard isCurrentOperation(operationVersion) else { return }
        try refreshProjection()
        guard try await advanceCompletedRounds(
            operationVersion: &operationVersion
        ) else { return }
        guard isCurrentOperation(operationVersion) else { return }
        await scheduleCurrentActorIfReady()
    }

    private func advanceCompletedRounds(
        operationVersion: inout Int
    ) async throws -> Bool {
        while store.cashSession?.phase == .handInProgress,
              store.cashSession?.currentActor == nil {
            guard isCurrentOperation(operationVersion) else { return false }
            let transition = try store.advanceIfRoundComplete()
            incrementStateVersion()
            operationVersion = stateVersion
            guard try await present(
                transition,
                guardedBy: operationVersion
            ) else { return false }
            guard isCurrentOperation(operationVersion) else { return false }
            try refreshProjection()
        }
        return true
    }

    private func present(
        _ transition: GameTransition,
        guardedBy operationVersion: Int
    ) async throws -> Bool {
        for event in transition.events {
            guard isCurrentOperation(operationVersion) else { return false }
            guard let animation = animation(for: event) else { continue }
            try refreshProjection(animation: animation)
            try await dependencies.sleep(.zero)
            guard isCurrentOperation(operationVersion) else { return false }
        }
        return true
    }

    private func isCurrentOperation(_ operationVersion: Int) -> Bool {
        stateVersion == operationVersion && state.phase != .suspended
    }

    private func cancelCountdown() {
        countdownTask.cancel()
    }

    private func cancelBotDecision() {
        botTask.cancel()
        guard let handID = currentHandID?.rawValue else { return }
        let service = botService
        Task { await service.cancel(handID: handID) }
    }

    private func showBotError() {
        botTask.clear()
        state = TableViewState(
            handID: state.handID,
            stateVersion: stateVersion,
            phase: state.phase,
            seats: state.seats,
            communityCards: state.communityCards,
            pot: state.pot,
            controls: nil,
            secondsRemaining: nil,
            winners: state.winners,
            errorMessage: "机器人行动失败，请重试。",
            animation: state.animation
        )
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

    nonisolated package static func requireBotPlayerObservation(
        _ observation: PlayerObservation?
    ) throws -> PlayerObservation {
        guard let observation else {
            throw PokerCoordinatorError.missingObservation
        }
        return observation
    }
}

private enum CountdownTickResult {
    case continueCountdown
    case performTimeout
    case stop
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

private final class BotTaskBox: @unchecked Sendable {
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
