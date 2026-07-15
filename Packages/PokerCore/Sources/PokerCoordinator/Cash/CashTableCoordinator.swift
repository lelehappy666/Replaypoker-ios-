import Observation
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

    private func refillBustedBotsToOneHundredBigBlinds() throws {
        guard let config = store.activeCashConfig,
              let session = store.cashSession
        else {
            throw PokerCoordinatorError.chipArithmeticOverflow
        }
        let (rawTarget, overflow) = config.bigBlind.rawValue
            .multipliedReportingOverflow(by: 100)
        guard !overflow, let target = Chips(rawValue: rawTarget) else {
            throw PokerCoordinatorError.chipArithmeticOverflow
        }

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

    private func refreshProjection(animation: TableAnimationEvent? = nil) throws {
        guard let currentHandID else {
            throw PokerCoordinatorError.missingObservation
        }
        state = try CashTableProjection.make(
            store: store,
            handID: currentHandID,
            stateVersion: stateVersion,
            humanSeat: humanSeat,
            seatProfiles: seatProfiles,
            animation: animation
        )
    }

    private func animation(for event: PublicGameEvent) -> TableAnimationEvent? {
        switch event {
        case let .blindPosted(seat, amount):
            return .postBlind(seat: seat, amount: amount)
        case let .holeCardsDealt(seat):
            return .dealHoleCard(seat: seat, card: .faceDown)
        default:
            return nil
        }
    }

    private func scheduleCurrentActorIfReady() async {}
}
