import Foundation
import PokerCore
import Testing
@testable import PokerSession

@Test func registrationRetryDoesNotChargeTwice() throws {
    let repository = TournamentLedgerMemoryRepository()
    let store = try LocalPokerStore(repository: repository, clock: tournamentLedgerClock)
    let request = try tournamentRegistrationRequest(id: "classic")
    let commandID = try BusinessID("register-classic")

    let first = try store.registerForTournament(request, businessID: commandID)
    let second = try store.registerForTournament(request, businessID: commandID)

    #expect(first == second)
    #expect(first.phase == .registered)
    #expect(store.accountBalance == (try Chips(992_000)))
    #expect(store.tournamentSessions == [first])
    #expect(try repository.load().ledger.entries.count == 1)
    _ = try roundTrip(try repository.load())
}

@Test func cancellationRetryRefundsOnceAndRemovesRegistration() throws {
    let repository = TournamentLedgerMemoryRepository()
    let store = try LocalPokerStore(repository: repository, clock: tournamentLedgerClock)
    let request = try tournamentRegistrationRequest(id: "cancel")
    _ = try store.registerForTournament(
        request,
        businessID: BusinessID("register-cancel")
    )
    let cancellationID = try BusinessID("cancel-cancel")

    let first = try store.cancelTournamentRegistration(
        request.id,
        businessID: cancellationID
    )
    let second = try store.cancelTournamentRegistration(
        request.id,
        businessID: cancellationID
    )

    #expect(first == second)
    #expect(store.tournamentSessions.isEmpty)
    #expect(store.accountBalance == SessionEconomy.initialBalance)
    #expect(try repository.load().ledger.entries.count == 2)
    _ = try roundTrip(try repository.load())
}

@Test func prizeRetryAwardsOnceAndFinishesTournament() throws {
    let session = try prizePendingTournamentSession(id: "prize", rank: 1)
    let repository = TournamentLedgerMemoryRepository(
        state: PersistedAppState(tournamentSessions: [session.id: session])
    )
    let store = try LocalPokerStore(repository: repository, clock: tournamentLedgerClock)
    let prizeID = try BusinessID("prize-payout")

    let first = try store.awardTournamentPrize(
        session.id,
        rank: 1,
        amount: try Chips(120_000),
        businessID: prizeID
    )
    let second = try store.awardTournamentPrize(
        session.id,
        rank: 1,
        amount: try Chips(120_000),
        businessID: prizeID
    )

    #expect(first == second)
    #expect(first.phase == .finished)
    #expect(store.accountBalance == (try Chips(1_120_000)))
    #expect(try repository.load().ledger.entries.count == 1)
    _ = try roundTrip(try repository.load())
}

@Test func tournamentCommandsRejectConflictingBusinessIdentifiers() throws {
    let store = try LocalPokerStore(
        repository: TournamentLedgerMemoryRepository(),
        clock: tournamentLedgerClock
    )
    let first = try tournamentRegistrationRequest(id: "first")
    let second = try tournamentRegistrationRequest(id: "second")
    let commandID = try BusinessID("shared-command")
    _ = try store.registerForTournament(first, businessID: commandID)

    #expect(throws: PokerSessionError.businessIDConflict) {
        try store.registerForTournament(second, businessID: commandID)
    }
    #expect(throws: PokerSessionError.businessIDConflict) {
        try store.cancelTournamentRegistration(first.id, businessID: commandID)
    }
}

private func tournamentRegistrationRequest(
    id: String
) throws -> TournamentRegistrationRequest {
    TournamentRegistrationRequest(
        id: try TournamentID(id),
        entryFee: try Chips(8_000),
        blindLevels: [
            BlindLevel(
                smallBlind: try Chips(50),
                bigBlind: try Chips(100),
                duration: .seconds(300)
            ),
        ],
        humanSeat: try SeatID(0),
        stacks: try Dictionary(uniqueKeysWithValues: (0..<9).map {
            (try SeatID($0), try Chips(20_000))
        })
    )
}

private func prizePendingTournamentSession(
    id: String,
    rank: Int
) throws -> TournamentSession {
    let human = try SeatID(0)
    let seats = try (0..<9).map { try SeatID($0) }
    var ranking = Array(seats.dropFirst())
    ranking.insert(human, at: 9 - rank)
    return try TournamentSession(
        id: TournamentID(id),
        phase: .prizePending,
        entryFee: try Chips(8_000),
        blindLevels: [
            BlindLevel(
                smallBlind: try Chips(50),
                bigBlind: try Chips(100),
                duration: .seconds(300)
            ),
        ],
        stacks: Dictionary(uniqueKeysWithValues: seats.map {
            ($0, try! Chips($0 == human ? 180_000 : 0))
        }),
        ranking: ranking,
        humanSeat: human
    )
}

private let tournamentLedgerClock = FixedSessionClock(
    now: Date(timeIntervalSince1970: 1_752_499_800),
    day: try! LocalDay("2026-07-14")
)

private final class TournamentLedgerMemoryRepository: SessionRepository {
    private var state: PersistedAppState

    init(state: PersistedAppState = PersistedAppState()) {
        self.state = state
    }

    func load() throws -> PersistedAppState { state }

    func save(_ state: PersistedAppState) throws {
        self.state = state
    }
}

private func roundTrip(_ state: PersistedAppState) throws -> PersistedAppState {
    try JSONDecoder().decode(
        PersistedAppState.self,
        from: JSONEncoder().encode(state)
    )
}
