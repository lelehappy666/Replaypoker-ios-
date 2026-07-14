import Foundation
import PokerCore
import Testing
@testable import PokerSession

@Test func unfinishedHandNeverAppearsInHistoryAfterReopen() throws {
    let directory = try RecoveryTemporaryDirectory()
    let store = try makeRecoveryStore(in: directory.url)
    _ = try store.startHand(id: HandID("unfinished"), seed: 17)

    #expect(store.handRecords().isEmpty)
    let reopened = try LocalPokerStore.open(directory: directory.url, clock: recoveryClock)
    #expect(reopened.handRecords().isEmpty)
    #expect(reopened.cashSession?.phase == .handInProgress)
}

@Test func completedHistoryContainsEveryDealtPlayersCardsAndSurvivesReopen() throws {
    let directory = try RecoveryTemporaryDirectory()
    let store = try makeRecoveryStore(in: directory.url)
    let stored = try completeAndCommitRecoveryHand(in: store, id: "history", seed: 23)
    let foldedSeats = Set(stored.record.actions.compactMap { action -> SeatID? in
        if case .fold = action.action { return action.seat }
        return nil
    })

    #expect(!foldedSeats.isEmpty)
    #expect(stored.record.holeCardsBySeat.count == 9)
    for seat in foldedSeats {
        #expect(stored.record.holeCardsBySeat[seat]?.count == 2)
    }

    let reopened = try LocalPokerStore.open(directory: directory.url, clock: recoveryClock)
    #expect(reopened.handRecords() == [stored])
}

@Test func fileRecoveryCoversReadyInProgressPendingAndCommittedStates() throws {
    let readyDirectory = try RecoveryTemporaryDirectory()
    let ready = try makeRecoveryStore(in: readyDirectory.url)
    let readyView = ready.cashSession
    #expect(
        try LocalPokerStore.open(directory: readyDirectory.url, clock: recoveryClock)
            .cashSession == readyView
    )

    let activeDirectory = try RecoveryTemporaryDirectory()
    let active = try makeRecoveryStore(in: activeDirectory.url)
    _ = try active.startHand(id: HandID("active"), seed: 29)
    let actor = try #require(active.spectatorObservation?.currentActor)
    _ = try active.apply(.fold, by: actor)
    let activeObservation = active.spectatorObservation
    let activePlayer = try active.playerObservation(for: SeatID(0))
    let reopenedActive = try LocalPokerStore.open(
        directory: activeDirectory.url,
        clock: recoveryClock
    )
    #expect(reopenedActive.spectatorObservation == activeObservation)
    #expect(try reopenedActive.playerObservation(for: SeatID(0)) == activePlayer)
    let reopenedActor = try #require(reopenedActive.spectatorObservation?.currentActor)
    let reopenedActorView = try #require(
        try reopenedActive.playerObservation(for: reopenedActor)
    )
    let reopenedLegal = try #require(reopenedActorView.legalActions)
    let continuedAction: PlayerAction
    if reopenedLegal.canFold {
        continuedAction = .fold
    } else if reopenedLegal.canCheck {
        continuedAction = .check
    } else {
        continuedAction = .call
    }
    _ = try reopenedActive.apply(continuedAction, by: reopenedActor)
    #expect(reopenedActive.spectatorObservation != activeObservation)

    let pendingDirectory = try RecoveryTemporaryDirectory()
    let pending = try makeRecoveryStore(in: pendingDirectory.url)
    try finishRecoveryHand(in: pending, id: "pending", seed: 31)
    let reopenedPending = try LocalPokerStore.open(
        directory: pendingDirectory.url,
        clock: recoveryClock
    )
    #expect(reopenedPending.cashSession?.phase == .settlementPending)
    #expect(reopenedPending.handRecords().isEmpty)

    let transactionID = try BusinessID("settle-pending")
    let committed = try reopenedPending.commitPendingHand(transactionID: transactionID)
    let reopenedCommitted = try LocalPokerStore.open(
        directory: pendingDirectory.url,
        clock: recoveryClock
    )
    #expect(reopenedCommitted.handRecords() == [committed])
    #expect(try reopenedCommitted.commitPendingHand(transactionID: transactionID) == committed)
    #expect(reopenedCommitted.statistics.completedHands == 1)
}

@Test func damagedRealFileIsRejectedWithoutResettingAccountOrHistory() throws {
    let directory = try RecoveryTemporaryDirectory()
    let store = try makeRecoveryStore(in: directory.url)
    _ = try completeAndCommitRecoveryHand(in: store, id: "before-damage", seed: 37)
    let file = directory.url.appendingPathComponent("river-club-state-v1.json")
    try Data("{ damaged".utf8).write(to: file)

    #expect(throws: PokerSessionError.corruptSnapshot) {
        try LocalPokerStore.open(directory: directory.url, clock: recoveryClock)
    }
    #expect(try Data(contentsOf: file) == Data("{ damaged".utf8))
}

@Test func deletingHistoryIsAtomicAndPreservesLedgerSessionStatisticsAndReceipts() throws {
    let repository = RecoveryMemoryRepository()
    let store = try LocalPokerStore(repository: repository, clock: recoveryClock)
    _ = try store.sitDown(
        request: recoveryRequest(session: "delete-session", table: "jade"),
        businessID: BusinessID("delete-buy")
    )
    let first = try completeAndCommitRecoveryHand(in: store, id: "delete-1", seed: 41)
    let second = try completeAndCommitRecoveryHand(in: store, id: "delete-2", seed: 43)
    let balance = store.accountBalance
    let session = store.cashSession
    let statistics = store.statistics
    let receipts = try repository.load().commandReceipts

    try store.deleteHand(id: first.id)
    #expect(store.handRecords() == [second])
    #expect(store.accountBalance == balance)
    #expect(store.cashSession == session)
    #expect(store.statistics == statistics)
    #expect(try repository.load().commandReceipts == receipts)

    try store.deleteAllHands(confirmation: .confirmed)
    #expect(store.handRecords().isEmpty)
    #expect(store.accountBalance == balance)
    #expect(store.cashSession == session)
    #expect(store.statistics == statistics)
    #expect(store.statistics.completedHands == 2)
    #expect(try repository.load().commandReceipts == receipts)
}

@Test func failedHistoryDeletionDoesNotPublishPartialMutation() throws {
    let repository = RecoveryMemoryRepository()
    let store = try LocalPokerStore(repository: repository, clock: recoveryClock)
    _ = try store.sitDown(
        request: recoveryRequest(session: "delete-failure", table: "jade"),
        businessID: BusinessID("delete-failure-buy")
    )
    let record = try completeAndCommitRecoveryHand(in: store, id: "keep", seed: 47)
    repository.failNextSave = true

    #expect(throws: PokerSessionError.persistenceFailed) {
        try store.deleteHand(id: record.id)
    }
    #expect(store.handRecords() == [record])
    #expect(try repository.load().records[record.id] == record)
    #expect(throws: PokerSessionError.recordNotFound) {
        try store.deleteHand(id: HandID("missing"))
    }
}

@Test func historyFiltersByFrozenTableAndLocalDayInNewestFirstOrder() throws {
    let repository = RecoveryMemoryRepository()
    let firstClock = FixedSessionClock(
        now: Date(timeIntervalSince1970: 1_752_499_800),
        day: try LocalDay("2026-07-14")
    )
    let firstStore = try LocalPokerStore(repository: repository, clock: firstClock)
    _ = try firstStore.sitDown(
        request: recoveryRequest(session: "filter-one", table: "jade"),
        businessID: BusinessID("filter-buy-one")
    )
    let first = try completeAndCommitRecoveryHand(in: firstStore, id: "filter-1", seed: 53)
    try firstStore.leave(businessID: BusinessID("filter-leave-one"))

    let secondClock = FixedSessionClock(
        now: Date(timeIntervalSince1970: 1_752_586_200),
        day: try LocalDay("2026-07-15")
    )
    let secondStore = try LocalPokerStore(repository: repository, clock: secondClock)
    _ = try secondStore.sitDown(
        request: recoveryRequest(session: "filter-two", table: "ruby"),
        businessID: BusinessID("filter-buy-two")
    )
    let second = try completeAndCommitRecoveryHand(in: secondStore, id: "filter-2", seed: 59)

    #expect(secondStore.handRecords() == [second, first])
    let jade = try TableID("jade")
    let secondDay = try LocalDay("2026-07-15")
    #expect(secondStore.handRecords(filter: HandRecordFilter(table: jade)) == [first])
    #expect(
        secondStore.handRecords(filter: HandRecordFilter(localDay: secondDay))
            == [second]
    )
}

private let recoveryClock = FixedSessionClock(
    now: Date(timeIntervalSince1970: 1_752_499_800),
    day: try! LocalDay("2026-07-14")
)

private final class RecoveryTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("river-club-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

private final class RecoveryMemoryRepository: SessionRepository {
    private var state = PersistedAppState()
    var failNextSave = false

    func load() throws -> PersistedAppState { state }

    func save(_ state: PersistedAppState) throws {
        if failNextSave {
            failNextSave = false
            throw PokerSessionError.persistenceFailed
        }
        self.state = state
    }
}

private func makeRecoveryStore(in directory: URL) throws -> LocalPokerStore {
    let store = try LocalPokerStore.open(directory: directory, clock: recoveryClock)
    _ = try store.sitDown(
        request: recoveryRequest(session: "recovery-session", table: "jade"),
        businessID: BusinessID("recovery-buy")
    )
    return store
}

private func recoveryRequest(session: String, table: String) throws -> CashTableRequest {
    let human = try SeatID(0)
    return CashTableRequest(
        sessionID: try SessionID(session),
        table: try TableID(table),
        config: try HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: human
        ),
        humanSeat: human,
        stacks: try Dictionary(uniqueKeysWithValues: (0..<9).map {
            (try SeatID($0), try Chips(4_000))
        })
    )
}

private func finishRecoveryHand(
    in store: LocalPokerStore,
    id: String,
    seed: UInt64
) throws {
    _ = try store.startHand(id: HandID(id), seed: seed)
    while let actor = store.spectatorObservation?.currentActor {
        _ = try store.apply(.fold, by: actor)
    }
    if store.cashSession?.phase == .handInProgress {
        _ = try store.advanceIfRoundComplete()
    }
    #expect(store.cashSession?.phase == .settlementPending)
}

private func completeAndCommitRecoveryHand(
    in store: LocalPokerStore,
    id: String,
    seed: UInt64
) throws -> StoredHandRecord {
    try finishRecoveryHand(in: store, id: id, seed: seed)
    return try store.commitPendingHand(transactionID: BusinessID("settle-\(id)"))
}
