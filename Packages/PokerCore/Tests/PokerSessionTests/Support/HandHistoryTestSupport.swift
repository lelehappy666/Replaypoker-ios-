import Foundation
import PokerCore
import Testing
@testable import PokerSession

func makeArchiveMetadata(
    tableName: String = "测试牌桌",
    humanSeat: SeatID = SeatID(rawValue: 0)!
) throws -> HandArchiveMetadata {
    try HandArchiveMetadata(
        tableDisplayName: tableName,
        humanSeat: humanSeat,
        seatDisplayNames: Dictionary(uniqueKeysWithValues: try (0..<9).map { index in
            (try SeatID(index), "玩家\(index + 1)")
        })
    )
}

func storedRecord(
    id: String,
    archiveMetadata: HandArchiveMetadata? = nil
) throws -> StoredHandRecord {
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let game = try HoldemGame.start(
        config: try HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(4_000), seat1: try Chips(4_000)],
        seed: 7
    )
    let actor = try #require(game.spectatorObservation().currentActor)
    try game.apply(.fold, by: actor)
    try game.advanceIfRoundComplete()

    return StoredHandRecord(
        id: try HandID(id),
        sessionID: try SessionID("session-\(id)"),
        table: try TableID("jade"),
        startedAt: Date(timeIntervalSince1970: 10),
        endedAt: Date(timeIntervalSince1970: 20),
        localDay: try LocalDay("2026-07-14"),
        handNumber: 1,
        record: try game.completedRecord(),
        archiveMetadata: archiveMetadata
    )
}

struct HistoryQueryFixture {
    let store: LocalPokerStore
    private let clock: HistoryQueryClock

    init() throws {
        let clock = HistoryQueryClock(
            now: Date(timeIntervalSince1970: 0),
            day: try LocalDay("2027-01-01")
        )
        self.clock = clock
        store = try LocalPokerStore(
            repository: HistoryQueryRepository(),
            clock: clock
        )
    }

    func save(
        table: String,
        day: String,
        endedAt: TimeInterval,
        hand: Int
    ) throws {
        clock.now = Date(timeIntervalSince1970: endedAt)
        clock.currentDay = try LocalDay(day)
        let humanSeat = try SeatID(0)
        let tableID = try TableID(table)
        if let activeTable = store.cashSession?.table, activeTable != tableID {
            try store.leave(businessID: try BusinessID("history-leave-\(hand)"))
        }
        if store.cashSession == nil {
            let request = CashTableRequest(
                sessionID: try SessionID("history-session-\(hand)"),
                table: tableID,
                config: try HandConfig(
                    smallBlind: try Chips(50),
                    bigBlind: try Chips(100),
                    dealer: humanSeat
                ),
                humanSeat: humanSeat,
                stacks: try Dictionary(uniqueKeysWithValues: (0..<9).map {
                    (try SeatID($0), try Chips(4_000))
                })
            )
            _ = try store.sitDown(
                request: request,
                businessID: try BusinessID("history-buy-\(hand)")
            )
        }
        _ = try store.startHand(id: try HandID("history-hand-\(hand)"), seed: UInt64(hand))
        while let actor = store.spectatorObservation?.currentActor {
            _ = try store.apply(.fold, by: actor)
        }
        if store.cashSession?.phase == .handInProgress {
            _ = try store.advanceIfRoundComplete()
        }
        _ = try store.commitPendingHand(
            transactionID: try BusinessID("history-settle-\(hand)"),
            archiveMetadata: makeArchiveMetadata()
        )
    }
}

private final class HistoryQueryClock: SessionClock, @unchecked Sendable {
    var now: Date
    var currentDay: LocalDay

    init(now: Date, day: LocalDay) {
        self.now = now
        currentDay = day
    }
}

private final class HistoryQueryRepository: SessionRepository {
    private var state = PersistedAppState()

    func load() throws -> PersistedAppState { state }

    func save(_ state: PersistedAppState) throws {
        self.state = state
    }
}
