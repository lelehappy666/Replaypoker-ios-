import Foundation
import PokerCore
import Testing
@testable import PokerSession

@Test func tournamentSessionRoundTripsAllRecoveryState() throws {
    let session = try makeTournamentSession()
    let state = PersistedAppState(tournamentSessions: [session.id: session])

    let reopened = try JSONDecoder().decode(
        PersistedAppState.self,
        from: JSONEncoder().encode(state)
    )

    #expect(reopened.tournamentSessions[session.id] == session)
    #expect(reopened.tournamentSessions[session.id]?.view == session.view)
}

@Test func versionFourStoreMigratesWithNoTournamentSessions() throws {
    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(PersistedAppState()))
            as? [String: Any]
    )
    object["version"] = 4
    object.removeValue(forKey: "tournamentSessions")

    let reopened = try JSONDecoder().decode(
        PersistedAppState.self,
        from: JSONSerialization.data(withJSONObject: object)
    )

    #expect(reopened.version == PersistedAppState.currentVersion)
    #expect(reopened.tournamentSessions.isEmpty)
}

@Test func storePublishesPersistedTournamentSessionsInStableOrder() throws {
    let first = try makeTournamentSession(id: "a-tournament")
    let second = try makeTournamentSession(id: "b-tournament")
    let repository = TournamentMemoryRepository(
        state: PersistedAppState(tournamentSessions: [second.id: second, first.id: first])
    )
    let store = try LocalPokerStore(repository: repository, clock: tournamentClock)

    #expect(store.tournamentSessions.map(\.id) == [first.id, second.id])
}

private func makeTournamentSession(
    id: String = "recovery-tournament"
) throws -> TournamentSession {
    let humanSeat = try SeatID(0)
    let stacks = try Dictionary(uniqueKeysWithValues: (0..<9).map {
        (try SeatID($0), try Chips($0 == 7 ? 0 : 10_000 + $0 * 100))
    })
    return try TournamentSession(
        id: TournamentID(id),
        phase: .active,
        blindLevels: [
            BlindLevel(
                smallBlind: try Chips(50),
                bigBlind: try Chips(100),
                duration: .seconds(300)
            ),
            BlindLevel(
                smallBlind: try Chips(100),
                bigBlind: try Chips(200),
                duration: .seconds(300)
            ),
        ],
        blindLevelIndex: 1,
        stacks: stacks,
        ranking: [try SeatID(7)],
        humanSeat: humanSeat
    )
}

private let tournamentClock = FixedSessionClock(
    now: Date(timeIntervalSince1970: 1_752_499_800),
    day: try! LocalDay("2026-07-14")
)

private final class TournamentMemoryRepository: SessionRepository {
    private var state: PersistedAppState

    init(state: PersistedAppState) {
        self.state = state
    }

    func load() throws -> PersistedAppState { state }

    func save(_ state: PersistedAppState) throws {
        self.state = state
    }
}
