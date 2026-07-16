import Foundation
import PokerCore
import PokerSession
@testable import RiverClub

@MainActor
struct HandHistoryAppFixture {
    let directory: URL
    let store: LocalPokerStore
    let session: AppSession

    private let cleanup: HandHistoryFixtureCleanup

    static func withThreeRecords() throws -> Self {
        try makeFixture()
    }

    static func withFailingDelete() throws -> Self {
        var dependencies = AppSessionDependencies.live
        dependencies.deleteHandRecord = { _, _ in
            throw PokerSessionError.persistenceFailed
        }
        dependencies.deleteAllHandRecords = { _ in
            throw PokerSessionError.persistenceFailed
        }
        return try makeFixture(dependencies: dependencies)
    }

    static func withActiveReadySessionAndRecords() throws -> Self {
        try makeFixture()
    }

    private static func makeFixture(
        dependencies: AppSessionDependencies = .live
    ) throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "river-club-hand-history-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        let clock = HandHistoryFixtureClock(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            currentDay: try LocalDay("2027-01-11")
        )
        let store = try LocalPokerStore.open(directory: directory, clock: clock)

        try archiveHand(
            number: 1,
            table: try TableID("table-a"),
            day: try LocalDay("2027-01-11"),
            store: store,
            clock: clock
        )
        try archiveHand(
            number: 2,
            table: try TableID("table-a"),
            day: try LocalDay("2027-01-12"),
            store: store,
            clock: clock
        )
        try store.leave(businessID: try BusinessID("history-leave-table-a"))
        try archiveHand(
            number: 3,
            table: try TableID("table-b"),
            day: try LocalDay("2027-01-12"),
            store: store,
            clock: clock
        )

        let session = AppSession(
            pokerStore: store,
            botSettingsRepository: MemoryBotSettingsRepository(initial: .recommended),
            dependencies: dependencies
        )
        return Self(
            directory: directory,
            store: store,
            session: session,
            cleanup: HandHistoryFixtureCleanup(directory: directory)
        )
    }

    private static func archiveHand(
        number: Int,
        table: TableID,
        day: LocalDay,
        store: LocalPokerStore,
        clock: HandHistoryFixtureClock
    ) throws {
        clock.currentDay = day
        clock.now = Date(timeIntervalSince1970: 1_800_000_000 + Double(number))
        let humanSeat = try SeatID(0)
        if store.cashSession == nil {
            let request = CashTableRequest(
                sessionID: try SessionID("history-session-\(table.rawValue)"),
                table: table,
                config: try HandConfig(
                    smallBlind: try Chips(50),
                    bigBlind: try Chips(100),
                    dealer: humanSeat
                ),
                humanSeat: humanSeat,
                stacks: try Dictionary(uniqueKeysWithValues: (0..<9).map { index in
                    (try SeatID(index), try Chips(4_000))
                })
            )
            _ = try store.sitDown(
                request: request,
                businessID: try BusinessID("history-sit-down-\(table.rawValue)")
            )
        }

        _ = try store.startHand(id: try HandID("history-hand-\(number)"))
        while let actor = store.spectatorObservation?.currentActor {
            _ = try store.apply(.fold, by: actor)
        }
        if store.cashSession?.phase == .handInProgress {
            _ = try store.advanceIfRoundComplete()
        }
        _ = try store.commitPendingHand(
            transactionID: try BusinessID("history-settle-\(number)"),
            archiveMetadata: try HandArchiveMetadata(
                tableDisplayName: table.rawValue,
                humanSeat: humanSeat,
                seatDisplayNames: Dictionary(uniqueKeysWithValues: try (0..<9).map { index in
                    (try SeatID(index), "玩家\(index + 1)")
                })
            )
        )
    }
}

private final class HandHistoryFixtureClock: SessionClock, @unchecked Sendable {
    var now: Date
    var currentDay: LocalDay

    init(now: Date, currentDay: LocalDay) {
        self.now = now
        self.currentDay = currentDay
    }
}

private final class HandHistoryFixtureCleanup {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
