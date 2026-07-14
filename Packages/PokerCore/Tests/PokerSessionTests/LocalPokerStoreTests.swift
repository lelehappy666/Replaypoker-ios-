import Foundation
import PokerCore
import Testing
@testable import PokerSession

@Test func sittingDownDebitsOnlyHumanBuyInAndPersistsTheWholeSession() throws {
    let repository = InMemorySessionRepository()
    let store = try LocalPokerStore(repository: repository, clock: storeClock)

    let view = try store.sitDown(
        request: try cashTableRequest(human: 4_000, bots: 9_000),
        businessID: try BusinessID("buy-jade-1")
    )

    #expect(view.phase == .readyForHand)
    #expect(view.seats.count == 9)
    #expect(store.accountBalance == (try Chips(124_500)))
    #expect(repository.saveCount == 1)
    #expect(try repository.load().activeCashSession?.view == view)
}

@Test func sittingDownRetryIsIdempotentAndConflictingParametersAreRejected() throws {
    let repository = InMemorySessionRepository()
    let store = try LocalPokerStore(repository: repository, clock: storeClock)
    let id = try BusinessID("buy-idempotent")
    let request = try cashTableRequest(human: 4_000)
    let first = try store.sitDown(request: request, businessID: id)

    let second = try store.sitDown(request: request, businessID: id)

    #expect(second == first)
    #expect(store.accountBalance == (try Chips(124_500)))
    #expect(throws: PokerSessionError.businessIDConflict) {
        try store.sitDown(
            request: cashTableRequest(human: 5_000),
            businessID: id
        )
    }
}

@Test func sittingDownAndRebuyCannotShareTheSameBuyInBusinessID() throws {
    let repository = InMemorySessionRepository()
    let store = try LocalPokerStore(repository: repository, clock: storeClock)
    let id = try BusinessID("buy-command-kind")
    _ = try store.sitDown(
        request: cashTableRequest(human: 4_000),
        businessID: id
    )

    #expect(throws: PokerSessionError.businessIDConflict) {
        try store.rebuyHuman(amount: Chips(4_000), businessID: id)
    }
    #expect(store.cashSession?.seats.first { $0.id == (try? SeatID(0)) }?.stack == (try Chips(4_000)))
}

@Test func delayedSitDownRetryRejectsChangedBotStackParameters() throws {
    let repository = InMemorySessionRepository()
    let store = try LocalPokerStore(repository: repository, clock: storeClock)
    let id = try BusinessID("buy-delayed")
    _ = try store.sitDown(
        request: cashTableRequest(human: 4_000),
        businessID: id
    )
    _ = try store.startHand(id: HandID("hand-delayed"), seed: 4)
    let before = store.spectatorObservation

    #expect(throws: PokerSessionError.businessIDConflict) {
        try store.sitDown(
            request: cashTableRequest(human: 4_000, bots: 5_000),
            businessID: id
        )
    }
    #expect(store.spectatorObservation == before)
}

@Test func failedSitDownSaveDoesNotExposeLedgerOrSessionChanges() throws {
    let repository = InMemorySessionRepository(failSavesFrom: 1)
    let store = try LocalPokerStore(repository: repository, clock: storeClock)

    #expect(throws: PokerSessionError.persistenceFailed) {
        try store.sitDown(
            request: cashTableRequest(human: 4_000),
            businessID: BusinessID("buy-fail")
        )
    }

    #expect(store.accountBalance == SessionEconomy.initialBalance)
    #expect(store.cashSession == nil)
    #expect(try repository.load() == PersistedAppState())
}

@Test func handCheckpointCommandsPersistAndFailureKeepsPublicObservationUnchanged() throws {
    let repository = InMemorySessionRepository()
    let store = try seatedStore(repository: repository)
    _ = try store.startHand(id: HandID("hand-atomic"), seed: 4)
    let actor = try #require(store.spectatorObservation?.currentActor)
    let before = store.spectatorObservation
    let committedBefore = try repository.load()
    repository.failSavesFrom = repository.saveCount + 1

    #expect(throws: PokerSessionError.persistenceFailed) {
        try store.apply(.fold, by: actor)
    }

    #expect(store.spectatorObservation == before)
    #expect(try repository.load() == committedBefore)
}

@Test func settlementRetryDoesNotDuplicateRecordStatisticsOrSessionProgress() throws {
    let repository = InMemorySessionRepository()
    let store = try completedPendingStore(repository: repository, handID: "hand-1")
    let transactionID = try BusinessID("settle-hand-1")

    let first = try store.commitPendingHand(transactionID: transactionID)
    let second = try store.commitPendingHand(transactionID: transactionID)

    #expect(first == second)
    #expect(first.transactionID == transactionID)
    #expect(store.handRecords().count == 1)
    #expect(store.statistics.completedHands == 1)
    #expect(store.cashSession?.completedHands == 1)
    #expect(store.cashSession?.phase == .readyForHand)
}

@Test func settlementRetrySurvivesReopenAfterPendingWasCleared() throws {
    let directory = try StoreTemporaryDirectory()
    let firstStore = try LocalPokerStore.open(directory: directory.url, clock: storeClock)
    try sitAndCompleteHand(in: firstStore, handID: "hand-reopen")
    let transactionID = try BusinessID("settle-reopen")
    let first = try firstStore.commitPendingHand(transactionID: transactionID)

    let reopened = try LocalPokerStore.open(directory: directory.url, clock: storeClock)
    let retried = try reopened.commitPendingHand(transactionID: transactionID)

    #expect(retried == first)
    #expect(reopened.handRecords() == [first])
    #expect(reopened.statistics.completedHands == 1)
    #expect(reopened.cashSession?.completedHands == 1)
}

@Test func settlementRejectsTransactionAndHandIdentityConflictsWithoutMutation() throws {
    let repository = InMemorySessionRepository()
    let store = try completedPendingStore(repository: repository, handID: "hand-first")
    let transactionID = try BusinessID("settle-shared")
    _ = try store.commitPendingHand(transactionID: transactionID)
    try completeAnotherHand(in: store, handID: "hand-second", seed: 7)
    let before = store.cashSession

    #expect(throws: PokerSessionError.businessIDConflict) {
        try store.commitPendingHand(transactionID: transactionID)
    }

    #expect(store.cashSession == before)
    #expect(store.handRecords().count == 1)
    #expect(store.statistics.completedHands == 1)
}

@Test func startingAHandRejectsAnAlreadyCommittedHandIDWithoutMutation() throws {
    let repository = InMemorySessionRepository()
    let store = try completedPendingStore(repository: repository, handID: "hand-reused")
    let transactionID = try BusinessID("settle-reused")
    _ = try store.commitPendingHand(transactionID: transactionID)
    let before = store.cashSession

    #expect(throws: PokerSessionError.businessIDConflict) {
        try store.startHand(id: HandID("hand-reused"), seed: 99)
    }

    #expect(store.cashSession == before)
    #expect(store.cashSession?.phase == .readyForHand)
    #expect(store.handRecords().count == 1)
}

@Test func ledgerAndSettlementCommandsRejectCrossDomainBusinessIDReuse() throws {
    let repository = InMemorySessionRepository()
    let store = try completedPendingStore(repository: repository, handID: "hand-cross-domain")

    #expect(throws: PokerSessionError.businessIDConflict) {
        try store.commitPendingHand(transactionID: BusinessID("buy-4000"))
    }

    let settlementID = try BusinessID("settle-cross-domain")
    _ = try store.commitPendingHand(transactionID: settlementID)
    #expect(throws: PokerSessionError.businessIDConflict) {
        try store.claimDailyGift(businessID: settlementID)
    }
}

@Test func commandLedgerIdentityIsAuditableAndSettlementDomainIsDisjoint() throws {
    let repository = InMemorySessionRepository()
    let store = try completedPendingStore(repository: repository, handID: "domain-hand")
    _ = try store.commitPendingHand(transactionID: BusinessID("domain-settlement"))
    let state = try repository.load()
    let ledgerIDs = Set(state.ledger.entries.map(\.businessID))
    let commandIDs = Set(state.commandReceipts.keys)
    let settlementIDs = Set(state.settlementReceipts.keys)

    #expect(ledgerIDs.contains(try BusinessID("buy-4000")))
    #expect(commandIDs.contains(try BusinessID("buy-4000")))
    #expect(ledgerIDs.isDisjoint(with: settlementIDs))
    #expect(commandIDs.isDisjoint(with: settlementIDs))
}

@Test func ledgerPreservesEvenPrefixLikeCallerBusinessIdentifierExactly() throws {
    let repository = InMemorySessionRepository()
    let store = try LocalPokerStore(repository: repository, clock: storeClock)
    let id = try BusinessID("__riverclub_internal_ledger__:caller-value")
    _ = try store.sitDown(request: cashTableRequest(human: 4_000), businessID: id)

    #expect(try repository.load().ledger.entries.last?.businessID == id)
}

@Test func aggregateRejectsCommandReceiptWhoseSessionTombstoneWasRemoved() throws {
    let repository = InMemorySessionRepository()
    let store = try seatedStore(repository: repository)
    var states = [try repository.load()]
    _ = try store.rebuyHuman(amount: Chips(100), businessID: BusinessID("receipt-rebuy"))
    states.append(try repository.load())
    try store.leave(businessID: BusinessID("receipt-cashout"))
    states.append(try repository.load())
    let zeroSession = try SessionID("receipt-zero-session")
    states.append(PersistedAppState(
        commandReceipts: [
            try BusinessID("receipt-zero"): .zeroStackLeave(
                sessionID: zeroSession,
                table: try TableID("jade")
            ),
        ],
        usedSessionIDs: [zeroSession]
    ))

    for state in states {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
                as? [String: Any]
        )
        object.removeValue(forKey: "activeCashSession")
        object["usedSessionIDs"] = []
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                PersistedAppState.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }
}

@Test func versionTwoRejectsIndividuallyRemovedCashCommandReceipt() throws {
    let repository = InMemorySessionRepository()
    let store = try seatedStore(repository: repository)
    let buyState = try repository.load()
    try store.leave(businessID: BusinessID("removed-receipt-cashout"))
    let cashOutState = try repository.load()

    for (state, removedID) in [
        (buyState, "buy-4000"),
        (cashOutState, "removed-receipt-cashout"),
    ] {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
                as? [String: Any]
        )
        var receipts = try #require(object["commandReceipts"] as? [String: Any])
        receipts.removeValue(forKey: removedID)
        object["commandReceipts"] = receipts
        #expect(throws: DecodingError.self, Comment(rawValue: removedID)) {
            try JSONDecoder().decode(
                PersistedAppState.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }
}

@Test func migratedVersionOneCashCommandsKeepExactLedgerFallbackIdempotency() throws {
    let sitRepository = InMemorySessionRepository()
    let sitStore = try seatedStore(repository: sitRepository)
    let sitRequest = try cashTableRequest(human: 4_000)
    let migratedSit = try migratedEarlyVersionOneState(from: sitRepository)
    let sitRetryRepository = InMemorySessionRepository(state: migratedSit)
    let sitRetryStore = try LocalPokerStore(
        repository: sitRetryRepository,
        clock: storeClock
    )
    #expect(
        try sitRetryStore.sitDown(
            request: sitRequest,
            businessID: BusinessID("buy-4000")
        ) == sitStore.cashSession
    )
    #expect(sitRetryRepository.saveCount == 0)

    let rebuyID = try BusinessID("legacy-rebuy")
    _ = try sitStore.rebuyHuman(amount: Chips(100), businessID: rebuyID)
    let migratedRebuy = try migratedEarlyVersionOneState(from: sitRepository)
    let rebuyRetryRepository = InMemorySessionRepository(state: migratedRebuy)
    let rebuyRetryStore = try LocalPokerStore(
        repository: rebuyRetryRepository,
        clock: storeClock
    )
    #expect(
        try rebuyRetryStore.rebuyHuman(amount: Chips(100), businessID: rebuyID)
            == sitStore.cashSession
    )
    #expect(rebuyRetryRepository.saveCount == 0)

    let leaveID = try BusinessID("legacy-cashout")
    try sitStore.leave(businessID: leaveID)
    let migratedLeave = try migratedEarlyVersionOneState(from: sitRepository)
    let leaveRetryRepository = InMemorySessionRepository(state: migratedLeave)
    let leaveRetryStore = try LocalPokerStore(
        repository: leaveRetryRepository,
        clock: storeClock
    )
    try leaveRetryStore.leave(businessID: leaveID)
    #expect(leaveRetryStore.cashSession == nil)
    #expect(leaveRetryRepository.saveCount == 0)
}

@Test func migratedVersionOneCashFallbackStillRejectsConflictingParametersAndKinds() throws {
    let repository = InMemorySessionRepository()
    _ = try seatedStore(repository: repository)
    let migrated = try migratedEarlyVersionOneState(from: repository)
    let retryStore = try LocalPokerStore(
        repository: InMemorySessionRepository(state: migrated),
        clock: storeClock
    )

    #expect(throws: PokerSessionError.businessIDConflict) {
        try retryStore.sitDown(
            request: cashTableRequest(human: 4_001),
            businessID: BusinessID("buy-4000")
        )
    }
    #expect(throws: PokerSessionError.businessIDConflict) {
        try retryStore.sitDown(
            request: cashTableRequest(human: 4_000, bots: 4_001),
            businessID: BusinessID("buy-4000")
        )
    }
    #expect(throws: PokerSessionError.businessIDConflict) {
        try retryStore.claimDailyGift(businessID: BusinessID("buy-4000"))
    }
}

@Test func migratedVersionOneBuyInsCannotReplayAcrossCommandKinds() throws {
    let repository = InMemorySessionRepository()
    let store = try seatedStore(repository: repository)
    let rebuyID = try BusinessID("typed-legacy-rebuy")
    _ = try store.rebuyHuman(amount: Chips(100), businessID: rebuyID)
    _ = try store.startHand(id: HandID("typed-legacy-hand"), seed: 83)
    let migrated = try migratedEarlyVersionOneState(from: repository)
    let retryRepository = InMemorySessionRepository(state: migrated)
    let retryStore = try LocalPokerStore(repository: retryRepository, clock: storeClock)

    #expect(throws: PokerSessionError.businessIDConflict) {
        try retryStore.rebuyHuman(
            amount: Chips(4_000),
            businessID: BusinessID("buy-4000")
        )
    }
    #expect(throws: PokerSessionError.businessIDConflict) {
        try retryStore.sitDown(
            request: cashTableRequest(human: 100),
            businessID: rebuyID
        )
    }
    #expect(
        try retryStore.rebuyHuman(amount: Chips(100), businessID: rebuyID)
            == store.cashSession
    )
    #expect(retryRepository.saveCount == 0)
}

@Test func migratedClosedVersionOneBuyInCannotAttachToNewActiveSession() throws {
    let repository = InMemorySessionRepository()
    let store = try seatedStore(repository: repository)
    try store.leave(businessID: BusinessID("typed-old-cashout"))
    _ = try store.sitDown(
        request: cashTableRequest(
            human: 4_000,
            sessionID: "typed-new-session"
        ),
        businessID: BusinessID("typed-new-buy")
    )
    let migrated = try migratedEarlyVersionOneState(from: repository)
    let retryStore = try LocalPokerStore(
        repository: InMemorySessionRepository(state: migrated),
        clock: storeClock
    )

    #expect(throws: PokerSessionError.businessIDConflict) {
        try retryStore.rebuyHuman(
            amount: Chips(4_000),
            businessID: BusinessID("buy-4000")
        )
    }
    #expect(throws: PokerSessionError.businessIDConflict) {
        try retryStore.sitDown(
            request: cashTableRequest(
                human: 4_000,
                sessionID: "typed-new-session"
            ),
            businessID: BusinessID("buy-4000")
        )
    }
}

@Test func aggregateRejectsForgedLegacyCashSegmentClassification() throws {
    let repository = InMemorySessionRepository()
    let store = try seatedStore(repository: repository)
    try store.leave(businessID: BusinessID("forged-segment-cashout"))
    _ = try store.sitDown(
        request: cashTableRequest(human: 4_000, sessionID: "forged-segment-new"),
        businessID: BusinessID("forged-segment-new-buy")
    )
    var migrated = try migratedEarlyVersionOneState(from: repository)
    migrated.commandReceipts[try BusinessID("buy-4000")] = .legacyCashBuyIn(
        kind: .sitDown,
        table: try TableID("jade"),
        amount: try Chips(4_000),
        belongsToOpenSession: true
    )

    #expect(throws: EncodingError.self) {
        try JSONEncoder().encode(migrated)
    }
}

@Test func savedLegacyGenericVersionTwoCashReceiptsMigrateAndRetryWithoutSaving() throws {
    let sitRepository = InMemorySessionRepository()
    let sitStore = try seatedStore(repository: sitRepository)
    let sitV2 = try savedLegacyGenericVersionTwoState(from: sitRepository)
    let sitRetryRepository = InMemorySessionRepository(state: sitV2)
    let sitRetryStore = try LocalPokerStore(
        repository: sitRetryRepository,
        clock: storeClock
    )
    #expect(
        try sitRetryStore.sitDown(
            request: cashTableRequest(human: 4_000),
            businessID: BusinessID("buy-4000")
        ) == sitStore.cashSession
    )
    #expect(sitRetryRepository.saveCount == 0)

    let rebuyID = try BusinessID("saved-v2-rebuy")
    _ = try sitStore.rebuyHuman(amount: Chips(100), businessID: rebuyID)
    let rebuyV2 = try savedLegacyGenericVersionTwoState(from: sitRepository)
    let rebuyRetryRepository = InMemorySessionRepository(state: rebuyV2)
    let rebuyRetryStore = try LocalPokerStore(
        repository: rebuyRetryRepository,
        clock: storeClock
    )
    #expect(
        try rebuyRetryStore.rebuyHuman(amount: Chips(100), businessID: rebuyID)
            == sitStore.cashSession
    )
    #expect(rebuyRetryRepository.saveCount == 0)

    let leaveID = try BusinessID("saved-v2-cashout")
    try sitStore.leave(businessID: leaveID)
    let leaveV2 = try savedLegacyGenericVersionTwoState(from: sitRepository)
    let leaveRetryRepository = InMemorySessionRepository(state: leaveV2)
    let leaveRetryStore = try LocalPokerStore(
        repository: leaveRetryRepository,
        clock: storeClock
    )
    try leaveRetryStore.leave(businessID: leaveID)
    #expect(leaveRetryStore.cashSession == nil)
    #expect(leaveRetryRepository.saveCount == 0)
}

@Test func savedLegacyGenericVersionTwoKeepsKindsSegmentsAndNoncashEvidence() throws {
    let openRepository = InMemorySessionRepository()
    let openStore = try seatedStore(repository: openRepository)
    let rebuyID = try BusinessID("saved-v2-typed-rebuy")
    _ = try openStore.rebuyHuman(amount: Chips(100), businessID: rebuyID)
    let openV2 = try savedLegacyGenericVersionTwoState(from: openRepository)
    let openRetry = try LocalPokerStore(
        repository: InMemorySessionRepository(state: openV2),
        clock: storeClock
    )
    #expect(throws: PokerSessionError.businessIDConflict) {
        try openRetry.rebuyHuman(
            amount: Chips(4_000),
            businessID: BusinessID("buy-4000")
        )
    }
    #expect(throws: PokerSessionError.businessIDConflict) {
        try openRetry.sitDown(
            request: cashTableRequest(human: 100),
            businessID: rebuyID
        )
    }

    try openStore.leave(businessID: BusinessID("saved-v2-old-cashout"))
    _ = try openStore.sitDown(
        request: cashTableRequest(human: 4_000, sessionID: "saved-v2-new-session"),
        businessID: BusinessID("saved-v2-new-buy")
    )
    let closedV2 = try savedLegacyGenericVersionTwoState(from: openRepository)
    let closedRetry = try LocalPokerStore(
        repository: InMemorySessionRepository(state: closedV2),
        clock: storeClock
    )
    #expect(throws: PokerSessionError.businessIDConflict) {
        try closedRetry.rebuyHuman(
            amount: Chips(4_000),
            businessID: BusinessID("buy-4000")
        )
    }

    var ledger = EntertainmentChipLedger()
    let giftID = try BusinessID("saved-v2-generic-gift")
    let day = try LocalDay("2026-07-16")
    _ = try ledger.claimDailyGift(id: giftID, day: day, at: storeClock.now)
    var noncash = PersistedAppState(ledger: ledger)
    noncash.commandReceipts[giftID] = .legacyLedgerOnly(reason: .dailyGift(day: day))
    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(noncash))
            as? [String: Any]
    )
    object["version"] = 2
    let migratedNoncash = try JSONDecoder().decode(
        PersistedAppState.self,
        from: JSONSerialization.data(withJSONObject: object)
    )
    #expect(
        migratedNoncash.commandReceipts[giftID]
            == .legacyLedgerOnly(reason: .dailyGift(day: day))
    )

    var modernObject = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(try openRepository.load())
        ) as? [String: Any]
    )
    modernObject["version"] = 2
    let modernMigrated = try JSONDecoder().decode(
        PersistedAppState.self,
        from: JSONSerialization.data(withJSONObject: modernObject)
    )
    guard case .sitDown = modernMigrated.commandReceipts[
        try BusinessID("saved-v2-new-buy")
    ] else {
        Issue.record("现代入座收据不应被 v2 迁移改写")
        return
    }
}

@Test func failedSettlementSaveLeavesPendingRecordAndStatisticsUnpublished() throws {
    let repository = InMemorySessionRepository()
    let store = try completedPendingStore(repository: repository, handID: "hand-failed-settle")
    let beforeSession = store.cashSession
    repository.failSavesFrom = repository.saveCount + 1

    #expect(throws: PokerSessionError.persistenceFailed) {
        try store.commitPendingHand(transactionID: BusinessID("settle-failed"))
    }

    #expect(store.cashSession == beforeSession)
    #expect(store.handRecords().isEmpty)
    #expect(store.statistics.completedHands == 0)
}

@Test func settlementUpdatesCheckedHumanStatisticsFromCompletedRecord() throws {
    let repository = InMemorySessionRepository()
    let store = try completedPendingStore(repository: repository, handID: "hand-statistics")
    let pending = try #require(try repository.load().activeCashSession?.pendingHand)
    let human = try SeatID(0)
    let expectedCommitted = try #require(pending.record.settledCommitments[human]).rawValue
    let expectedDelta = try #require(pending.record.chipDeltas[human])
    let expectedWonHands = pending.record.awards[human] == nil ? 0 : 1

    _ = try store.commitPendingHand(transactionID: BusinessID("settle-statistics"))

    #expect(store.statistics.completedHands == 1)
    #expect(store.statistics.wonHands == expectedWonHands)
    #expect(store.statistics.totalCommitted == expectedCommitted)
    #expect(store.statistics.netChange == expectedDelta)
    #expect(store.statistics.largestWin == max(0, expectedDelta))
}

@Test func leavingReturnsExactHumanStackAndRetryIsANoOp() throws {
    let repository = InMemorySessionRepository()
    let store = try seatedStore(repository: repository, human: 6_250)
    let id = try BusinessID("leave-jade-1")

    try store.leave(businessID: id)
    try store.leave(businessID: id)

    #expect(store.accountBalance == (try Chips(128_500)))
    #expect(store.cashSession == nil)
    #expect(throws: PokerSessionError.businessIDConflict) {
        try store.claimDailyGift(businessID: id)
    }
}

@Test func leavingDuringHandOrPendingSettlementIsRejectedWithoutSaving() throws {
    let activeRepository = InMemorySessionRepository()
    let active = try seatedStore(repository: activeRepository)
    _ = try active.startHand(id: HandID("hand-active"), seed: 4)
    let activeSaveCount = activeRepository.saveCount
    #expect(throws: PokerSessionError.invalidLifecycle) {
        try active.leave(businessID: BusinessID("leave-active"))
    }
    #expect(activeRepository.saveCount == activeSaveCount)

    let pendingRepository = InMemorySessionRepository()
    let pending = try completedPendingStore(repository: pendingRepository, handID: "hand-pending")
    let pendingSaveCount = pendingRepository.saveCount
    #expect(throws: PokerSessionError.settlementPending) {
        try pending.leave(businessID: BusinessID("leave-pending"))
    }
    #expect(pendingRepository.saveCount == pendingSaveCount)
}

@Test func rebuyDebitsOnceAndConflictingAmountIsRejected() throws {
    let repository = InMemorySessionRepository()
    let store = try seatedStore(repository: repository, human: 4_000)
    try completeHand(in: store, handID: "hand-bust", seed: 12)
    _ = try store.commitPendingHand(transactionID: BusinessID("settle-bust"))
    let current = try #require(store.cashSession?.seats.first { $0.id == (try? SeatID(0)) })
    let amount = try Chips(8_000 - current.stack.rawValue)
    let id = try BusinessID("rebuy-jade-1")
    let balanceBefore = store.accountBalance

    let first = try store.rebuyHuman(amount: amount, businessID: id)
    let second = try store.rebuyHuman(amount: amount, businessID: id)

    #expect(second == first)
    #expect(store.accountBalance.rawValue == balanceBefore.rawValue - amount.rawValue)
    #expect(throws: PokerSessionError.businessIDConflict) {
        try store.rebuyHuman(amount: Chips(amount.rawValue - 1), businessID: id)
    }
}

@Test func dailyGiftAndReliefArePersistentIdempotentCommands() throws {
    let giftRepository = InMemorySessionRepository()
    let giftStore = try LocalPokerStore(repository: giftRepository, clock: storeClock)
    let giftID = try BusinessID("gift-1")
    let firstGift = try giftStore.claimDailyGift(businessID: giftID)
    let secondGift = try giftStore.claimDailyGift(businessID: giftID)
    #expect(secondGift == firstGift)
    #expect(giftStore.accountBalance == (try Chips(138_500)))

    let lowLedger = EntertainmentChipLedger(balance: try Chips(5_500))
    let reliefRepository = InMemorySessionRepository(state: PersistedAppState(ledger: lowLedger))
    let reliefStore = try seatedStore(repository: reliefRepository, human: 4_000)
    let reliefID = try BusinessID("relief-1")
    let firstRelief = try reliefStore.claimRelief(businessID: reliefID)
    let secondRelief = try reliefStore.claimRelief(businessID: reliefID)
    #expect(secondRelief == firstRelief)
    #expect(reliefStore.accountBalance == SessionEconomy.reliefTarget)
    #expect(reliefStore.cashSession != nil)
}

@Test func successfulGiftAndReliefRetriesDoNotSaveAgain() throws {
    let giftRepository = InMemorySessionRepository()
    let giftStore = try LocalPokerStore(repository: giftRepository, clock: storeClock)
    let giftID = try BusinessID("gift-no-resave")
    let gift = try giftStore.claimDailyGift(businessID: giftID)
    giftRepository.failSavesFrom = giftRepository.saveCount + 1
    #expect(try giftStore.claimDailyGift(businessID: giftID) == gift)

    let lowLedger = EntertainmentChipLedger(balance: try Chips(1_500))
    let reliefRepository = InMemorySessionRepository(state: PersistedAppState(ledger: lowLedger))
    let reliefStore = try LocalPokerStore(repository: reliefRepository, clock: storeClock)
    let reliefID = try BusinessID("relief-no-resave")
    let relief = try reliefStore.claimRelief(businessID: reliefID)
    reliefRepository.failSavesFrom = reliefRepository.saveCount + 1
    #expect(try reliefStore.claimRelief(businessID: reliefID) == relief)
}

@Test func zeroStackLeaveClearsSessionAndRetrySurvivesReopen() throws {
    let directory = try StoreTemporaryDirectory()
    let repository = FileSessionRepository(directory: directory.url)
    var session = try CashGameSession.make(
        id: SessionID("session-zero-leave"),
        table: TableID("jade"),
        config: cashTableRequest(human: 4_000).config,
        humanSeat: SeatID(0),
        stacks: cashTableRequest(human: 4_000).stacks
    )
    session.stacks[try SeatID(0)] = try Chips(0)
    let ledger = EntertainmentChipLedger(balance: try Chips(124_500))
    try repository.save(PersistedAppState(ledger: ledger, activeCashSession: session))
    let id = try BusinessID("leave-zero")

    let store = try LocalPokerStore.open(directory: directory.url, clock: storeClock)
    try store.leave(businessID: id)
    #expect(store.cashSession == nil)
    #expect(store.accountBalance == (try Chips(124_500)))

    let reopened = try LocalPokerStore.open(directory: directory.url, clock: storeClock)
    try reopened.leave(businessID: id)
    #expect(reopened.cashSession == nil)
    #expect(reopened.accountBalance == (try Chips(124_500)))
}

@Test func aggregateRejectsRebuyReceiptWithInvalidPublicResult() throws {
    let id = try BusinessID("rebuy-corrupt-result")
    let table = try TableID("jade")
    let human = try SeatID(0)
    let amount = try Chips(4_000)
    var ledger = EntertainmentChipLedger()
    _ = try ledger.buyIn(amount: amount, table: table, id: id, at: storeClock.now)
    let invalid = CashSessionView(
        id: try SessionID("session-corrupt-receipt"),
        table: table,
        humanSeat: human,
        phase: .readyForHand,
        dealer: human,
        completedHands: 0,
        seats: [],
        currentActor: nil
    )
    let state = PersistedAppState(
        ledger: ledger,
        commandReceipts: [
            id: .rebuy(
                sessionID: invalid.id,
                table: table,
                humanSeat: human,
                amount: amount,
                before: invalid,
                result: invalid
            ),
        ]
    )

    #expect(throws: EncodingError.self) {
        try JSONEncoder().encode(state)
    }
}

@Test func aggregateRejectsSitDownReceiptWithDuplicatePublicSeatsWithoutCrashing() throws {
    let id = try BusinessID("sit-corrupt-seats")
    let request = try cashTableRequest(human: 4_000)
    var ledger = EntertainmentChipLedger()
    _ = try ledger.buyIn(
        amount: try Chips(4_000),
        table: request.table,
        id: id,
        at: storeClock.now
    )
    let valid = try CashGameSession.make(
        id: request.sessionID,
        table: request.table,
        config: request.config,
        humanSeat: request.humanSeat,
        stacks: request.stacks
    ).view
    let repeatedSeat = try #require(valid.seats.first)
    let invalid = CashSessionView(
        id: valid.id,
        table: valid.table,
        humanSeat: valid.humanSeat,
        phase: valid.phase,
        dealer: valid.dealer,
        completedHands: valid.completedHands,
        seats: Array(repeating: repeatedSeat, count: 9),
        currentActor: nil
    )
    let state = PersistedAppState(
        ledger: ledger,
        commandReceipts: [id: .sitDown(request: request, result: invalid)]
    )

    #expect(throws: EncodingError.self) {
        try JSONEncoder().encode(state)
    }
}

private let storeClock = FixedSessionClock(
    now: Date(timeIntervalSince1970: 1_752_499_800),
    day: try! LocalDay("2026-07-14")
)

private final class InMemorySessionRepository: SessionRepository {
    private var state: PersistedAppState
    var saveCount = 0
    var failSavesFrom: Int?

    init(state: PersistedAppState = PersistedAppState(), failSavesFrom: Int? = nil) {
        self.state = state
        self.failSavesFrom = failSavesFrom
    }

    func load() throws -> PersistedAppState { state }

    func save(_ state: PersistedAppState) throws {
        saveCount += 1
        if let failSavesFrom, saveCount >= failSavesFrom {
            throw PokerSessionError.persistenceFailed
        }
        self.state = state
    }
}

private func migratedEarlyVersionOneState(
    from repository: InMemorySessionRepository
) throws -> PersistedAppState {
    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(try repository.load()))
            as? [String: Any]
    )
    object["version"] = 1
    object.removeValue(forKey: "commandReceipts")
    object.removeValue(forKey: "usedHandIDs")
    object.removeValue(forKey: "usedSessionIDs")
    object.removeValue(forKey: "settlementReceipts")
    return try JSONDecoder().decode(
        PersistedAppState.self,
        from: JSONSerialization.data(withJSONObject: object)
    )
}

private func savedLegacyGenericVersionTwoState(
    from repository: InMemorySessionRepository
) throws -> PersistedAppState {
    var oldState = try repository.load()
    for entry in oldState.ledger.entries {
        switch entry.reason {
        case .cashBuyIn, .cashOut:
            oldState.commandReceipts[entry.businessID] = .legacyLedgerOnly(
                reason: entry.reason
            )
        case .dailyGift, .bankruptcyRelief:
            break
        }
    }
    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(oldState))
            as? [String: Any]
    )
    object["version"] = 2
    let fixture = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(PersistedAppState.self, from: fixture)
}

private final class StoreTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("river-club-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

private func cashTableRequest(
    human: Int,
    bots: Int = 4_000,
    sessionID: String = "session-jade",
    table: String = "jade"
) throws -> CashTableRequest {
    let humanSeat = try SeatID(0)
    return CashTableRequest(
        sessionID: try SessionID(sessionID),
        table: try TableID(table),
        config: try HandConfig(
            smallBlind: Chips(50),
            bigBlind: Chips(100),
            dealer: humanSeat
        ),
        humanSeat: humanSeat,
        stacks: try Dictionary(uniqueKeysWithValues: (0..<9).map { rawSeat in
            (try SeatID(rawSeat), try Chips(rawSeat == 0 ? human : bots))
        })
    )
}

private func seatedStore(
    repository: InMemorySessionRepository,
    human: Int = 4_000
) throws -> LocalPokerStore {
    let store = try LocalPokerStore(repository: repository, clock: storeClock)
    _ = try store.sitDown(
        request: cashTableRequest(human: human),
        businessID: BusinessID("buy-\(human)")
    )
    return store
}

private func completedPendingStore(
    repository: InMemorySessionRepository,
    handID: String
) throws -> LocalPokerStore {
    let store = try seatedStore(repository: repository)
    try completeHand(in: store, handID: handID, seed: 4)
    return store
}

private func sitAndCompleteHand(in store: LocalPokerStore, handID: String) throws {
    _ = try store.sitDown(
        request: cashTableRequest(human: 4_000),
        businessID: BusinessID("buy-\(handID)")
    )
    try completeHand(in: store, handID: handID, seed: 4)
}

private func completeAnotherHand(
    in store: LocalPokerStore,
    handID: String,
    seed: UInt64
) throws {
    try completeHand(in: store, handID: handID, seed: seed)
}

private func completeHand(
    in store: LocalPokerStore,
    handID: String,
    seed: UInt64
) throws {
    _ = try store.startHand(id: HandID(handID), seed: seed)
    while let actor = store.spectatorObservation?.currentActor {
        _ = try store.apply(.fold, by: actor)
    }
    if store.cashSession?.phase == .handInProgress {
        _ = try store.advanceIfRoundComplete()
    }
    #expect(store.cashSession?.phase == .settlementPending)
}
