import Foundation
import PokerCore
import PokerSession
import Testing

final class CoordinatorStoreFixture {
    let store: LocalPokerStore
    let bustedBot: SeatID
    let showdownSeat: SeatID
    let foldedSeat: SeatID
    let completedRecord: CompletedHandRecord

    private let directory: URL

    private init(
        store: LocalPokerStore,
        bustedBot: SeatID,
        showdownSeat: SeatID,
        foldedSeat: SeatID,
        completedRecord: CompletedHandRecord,
        directory: URL
    ) {
        self.store = store
        self.bustedBot = bustedBot
        self.showdownSeat = showdownSeat
        self.foldedSeat = foldedSeat
        self.completedRecord = completedRecord
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    static func finishedHandWithBustedBot() throws -> CoordinatorStoreFixture {
        let directory = try makeTemporaryDirectory(named: "finished-busted-bot")
        do {
            let lowStackBot = try SeatID(1)
            let store = try makeSeatedStore(
                directory: directory,
                botStackOverrides: [lowStackBot: try Chips(1)]
            )
            try playToShowdown(in: store, foldedSeat: nil, seed: 7)
            let record = try pendingRecord(in: directory)
            let humanSeat = try SeatID(0)
            let bustedBot = try #require(
                record.finalStacks.keys.sorted().first {
                    $0 != humanSeat && record.finalStacks[$0]?.rawValue == 0
                }
            )
            _ = try store.commitPendingHand(transactionID: try BusinessID("settle-busted-bot"))
            let showdownSeat = try #require(
                record.handRanksBySeat.keys.sorted().first { $0 != bustedBot }
            )
            return CoordinatorStoreFixture(
                store: store,
                bustedBot: bustedBot,
                showdownSeat: showdownSeat,
                foldedSeat: try SeatID(3),
                completedRecord: record,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func pendingShowdown() throws -> CoordinatorStoreFixture {
        let directory = try makeTemporaryDirectory(named: "pending-showdown")
        do {
            let foldedSeat = try SeatID(3)
            let store = try makeSeatedStore(directory: directory)
            try playToShowdown(in: store, foldedSeat: foldedSeat, seed: 11)
            let record = try pendingRecord(in: directory)
            let showdownSeat = try #require(
                record.handRanksBySeat.keys.sorted().first { $0 != foldedSeat }
            )
            return CoordinatorStoreFixture(
                store: store,
                bustedBot: try SeatID(1),
                showdownSeat: showdownSeat,
                foldedSeat: foldedSeat,
                completedRecord: record,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

private let coordinatorClock = FixedSessionClock(
    now: Date(timeIntervalSince1970: 1_752_499_800),
    day: try! LocalDay("2026-07-14")
)

private func makeTemporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "river-club-coordinator-\(name)-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

private func makeSeatedStore(
    directory: URL,
    botStackOverrides: [SeatID: Chips] = [:]
) throws -> LocalPokerStore {
    let humanSeat = try SeatID(0)
    let stacks = try Dictionary(uniqueKeysWithValues: (0..<9).map { rawSeat in
        let seat = try SeatID(rawSeat)
        let stack = try botStackOverrides[seat] ?? Chips(4_000)
        return (seat, stack)
    })
    let request = CashTableRequest(
        sessionID: try SessionID("coordinator-session"),
        table: try TableID("coordinator-table"),
        config: try HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: humanSeat
        ),
        humanSeat: humanSeat,
        stacks: stacks
    )
    let store = try LocalPokerStore.open(directory: directory, clock: coordinatorClock)
    _ = try store.sitDown(
        request: request,
        businessID: try BusinessID("coordinator-buy-in")
    )
    return store
}

private func playToShowdown(
    in store: LocalPokerStore,
    foldedSeat: SeatID?,
    seed: UInt64
) throws {
    _ = try store.startHand(id: try HandID("coordinator-hand"), seed: seed)
    var hasFoldedDesignatedSeat = false
    var remainingSteps = 200

    while store.cashSession?.phase == .handInProgress, remainingSteps > 0 {
        remainingSteps -= 1
        if let actor = store.cashSession?.currentActor {
            let observation = try #require(try store.playerObservation(for: actor))
            let legal = try #require(observation.legalActions)
            let action: PlayerAction
            if actor == foldedSeat, !hasFoldedDesignatedSeat, legal.canFold {
                action = .fold
                hasFoldedDesignatedSeat = true
            } else if legal.canCheck {
                action = .check
            } else if legal.callAmount != nil {
                action = .call
            } else {
                action = .fold
            }
            _ = try store.apply(action, by: actor)
        } else {
            _ = try store.advanceIfRoundComplete()
        }
    }

    #expect(remainingSteps > 0)
    #expect(store.cashSession?.phase == .settlementPending)
    if foldedSeat != nil {
        #expect(hasFoldedDesignatedSeat)
    }
}

private func pendingRecord(in directory: URL) throws -> CompletedHandRecord {
    try #require(
        FileSessionRepository(directory: directory)
            .load()
            .activeCashSession?
            .pendingHand?
            .record
    )
}
