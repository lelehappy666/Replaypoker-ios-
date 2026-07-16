import PokerCore
import PokerSession
import XCTest
@testable import RiverClub

final class HandHistorySessionTests: XCTestCase {
    @MainActor
    func testAvailableTablesIgnoreCurrentFiltersAndSelectionReadsCompletedRecord() throws {
        let fixture = try HandHistoryAppFixture.withThreeRecords()
        fixture.session.updateHandHistoryFilters(
            HandHistoryFilters(
                table: try TableID("table-a"),
                dateSelection: .custom(try LocalDay("2027-01-12"))
            )
        )

        fixture.session.loadHandHistory()

        XCTAssertEqual(
            Set(fixture.session.handHistoryState.availableTables.map(\.id)),
            Set([try TableID("table-a"), try TableID("table-b")])
        )
        let item = try XCTUnwrap(fixture.session.handHistoryState.items.first)
        fixture.session.selectHandHistory(id: item.id)
        XCTAssertEqual(fixture.session.handHistoryState.selection?.id, item.id)

        fixture.session.closeHandHistoryDetail()
        XCTAssertNil(fixture.session.handHistoryState.selection)
    }

    @MainActor
    func testLoadingHistoryUsesTheSameStoreAndCurrentFilters() throws {
        let fixture = try HandHistoryAppFixture.withThreeRecords()
        fixture.session.open(.tables)
        fixture.session.updateHandHistoryFilters(
            HandHistoryFilters(
                table: try TableID("table-a"),
                dateSelection: .custom(try LocalDay("2027-01-12"))
            )
        )

        fixture.session.loadHandHistory()

        XCTAssertEqual(fixture.session.handHistoryState.items.map(\.handNumber), [2])
        XCTAssertTrue(fixture.session.pokerStore === fixture.store)
    }

    @MainActor
    func testHistoryReadFailureKeepsErrorAndRetryAction() throws {
        var dependencies = AppSessionDependencies.live
        dependencies.loadHandRecords = { _, _ in
            throw PokerSessionError.persistenceFailed
        }
        let fixture = try AppSessionFixture(dependencies: dependencies)

        fixture.session.loadHandHistory()

        XCTAssertEqual(
            fixture.session.handHistoryState.loadState,
            .failed("牌局存档读取失败，请重试。")
        )
    }

    @MainActor
    func testLeavingTableForHistoryReloadsLatestRecords() throws {
        let fixture = try HandHistoryAppFixture.withThreeRecords()

        fixture.session.leaveTable(returningTo: .tables)

        XCTAssertEqual(fixture.session.handHistoryState.items.count, 3)
    }

    @MainActor
    func testUserSelectedCustomDateKeepsTheCurrentTableFilter() throws {
        let fixture = try HandHistoryAppFixture.withThreeRecords()
        let table = try TableID("table-a")
        fixture.session.updateHandHistoryFilters(
            HandHistoryFilters(table: table, dateSelection: .all)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(
            TimeZone(secondsFromGMT: 8 * 60 * 60)
        )
        let selectedDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2027, month: 1, day: 12, hour: 12)
            )
        )

        try fixture.session.selectCustomHandHistoryDate(
            selectedDate,
            calendar: calendar
        )

        XCTAssertEqual(
            fixture.session.handHistoryState.filters,
            HandHistoryFilters(
                table: table,
                dateSelection: .custom(try LocalDay("2027-01-12"))
            )
        )
        XCTAssertEqual(fixture.session.handHistoryState.items.map(\.handNumber), [2])
    }

    @MainActor
    func testClosingDetailRestoresTheSameListScrollTarget() throws {
        let fixture = try HandHistoryAppFixture.withThreeRecords()
        fixture.session.loadHandHistory()
        let target = try XCTUnwrap(
            fixture.session.handHistoryState.items.last?.id
        )
        fixture.session.updateHandHistoryScrollTarget(target)

        fixture.session.selectHandHistory(id: target)
        fixture.session.closeHandHistoryDetail()

        XCTAssertNil(fixture.session.handHistoryState.selection)
        XCTAssertEqual(
            fixture.session.handHistoryState.listScrollTarget,
            target
        )
    }

    @MainActor
    func testChangingFiltersResetsTheSavedListScrollTarget() throws {
        let fixture = try HandHistoryAppFixture.withThreeRecords()
        fixture.session.loadHandHistory()
        let target = try XCTUnwrap(
            fixture.session.handHistoryState.items.last?.id
        )
        fixture.session.updateHandHistoryScrollTarget(target)

        fixture.session.updateHandHistoryFilters(
            HandHistoryFilters(
                table: try TableID("table-a"),
                dateSelection: .all
            )
        )

        XCTAssertNil(fixture.session.handHistoryState.listScrollTarget)
    }

    @MainActor
    func testDeleteAllAvailabilityUsesSuccessfulGlobalLoadNotFilteredItems() throws {
        let fixture = try HandHistoryAppFixture.withThreeRecords()
        fixture.session.updateHandHistoryFilters(
            HandHistoryFilters(
                dateSelection: .custom(try LocalDay("2030-01-01"))
            )
        )

        XCTAssertTrue(fixture.session.handHistoryState.items.isEmpty)
        XCTAssertTrue(fixture.session.handHistoryState.canDeleteAll)
    }

    @MainActor
    func testDeleteAllIsDisabledForLoadingFailureAndNoGlobalRecords() throws {
        let fixture = try HandHistoryAppFixture.withThreeRecords()
        fixture.session.loadHandHistory()
        XCTAssertTrue(fixture.session.handHistoryState.canDeleteAll)

        var dependencies = AppSessionDependencies.live
        dependencies.loadHandRecords = { _, _ in
            throw PokerSessionError.persistenceFailed
        }
        let failing = AppSession(
            pokerStore: fixture.store,
            botSettingsRepository: MemoryBotSettingsRepository(
                initial: .recommended
            ),
            dependencies: dependencies
        )
        failing.loadHandHistory()
        XCTAssertFalse(failing.handHistoryState.canDeleteAll)

        try fixture.store.deleteAllHands(confirmation: .confirmed)
        fixture.session.loadHandHistory()
        XCTAssertFalse(fixture.session.handHistoryState.canDeleteAll)
    }

    @MainActor
    func testSingleDeleteRequiresConfirmationAndPreservesEconomyState() throws {
        let fixture = try HandHistoryAppFixture.withThreeRecords()
        fixture.session.loadHandHistory()
        let id = try XCTUnwrap(fixture.session.handHistoryState.items.first?.id)
        let balance = fixture.store.accountBalance
        let statistics = fixture.store.statistics
        let filters = HandHistoryFilters(
            table: try TableID("table-b"),
            dateSelection: .custom(try LocalDay("2027-01-12"))
        )

        fixture.session.requestDeleteHand(id: id)

        XCTAssertEqual(fixture.store.handRecords().count, 3)
        XCTAssertEqual(fixture.session.handHistoryState.pendingDeletion, .hand(id))

        fixture.session.cancelHistoryDeletion()

        XCTAssertEqual(fixture.store.handRecords().count, 3)
        XCTAssertNil(fixture.session.handHistoryState.pendingDeletion)
        XCTAssertNil(fixture.session.handHistoryState.deletionError)

        fixture.session.updateHandHistoryFilters(filters)
        fixture.session.selectHandHistory(id: id)
        fixture.session.requestDeleteHand(id: id)
        try fixture.session.confirmHistoryDeletion()

        XCTAssertEqual(fixture.store.handRecords().count, 2)
        XCTAssertEqual(fixture.store.accountBalance, balance)
        XCTAssertEqual(fixture.store.statistics, statistics)
        XCTAssertEqual(fixture.session.handHistoryState.filters, filters)
        XCTAssertNil(fixture.session.handHistoryState.pendingDeletion)
        XCTAssertNil(fixture.session.handHistoryState.selection)
        XCTAssertNil(fixture.session.handHistoryState.deletionError)
    }

    @MainActor
    func testDeleteFailureKeepsListSelectionAndOffersSameRetry() throws {
        var attemptedIDs: [HandID] = []
        let fixture = try HandHistoryAppFixture.withFailingDelete {
            attemptedIDs.append($0)
        }
        fixture.session.loadHandHistory()
        let before = fixture.session.handHistoryState.items
        let id = try XCTUnwrap(before.first?.id)
        fixture.session.selectHandHistory(id: id)
        let selection = fixture.session.handHistoryState.selection

        fixture.session.requestDeleteHand(id: id)
        XCTAssertThrowsError(try fixture.session.confirmHistoryDeletion())

        XCTAssertEqual(fixture.store.handRecords().count, 3)
        XCTAssertEqual(fixture.session.handHistoryState.items, before)
        XCTAssertEqual(fixture.session.handHistoryState.selection, selection)
        XCTAssertEqual(
            fixture.session.handHistoryState.deletionError,
            "牌局存档删除失败，请重试。"
        )
        XCTAssertEqual(fixture.session.handHistoryState.pendingDeletion, .hand(id))

        XCTAssertThrowsError(try fixture.session.confirmHistoryDeletion())
        XCTAssertEqual(fixture.session.handHistoryState.pendingDeletion, .hand(id))
        XCTAssertEqual(attemptedIDs, [id, id])
    }

    @MainActor
    func testCancellingDeletionClearsPendingAndOverlayState() throws {
        let fixture = try HandHistoryAppFixture.withThreeRecords()
        fixture.session.loadHandHistory()
        let id = try XCTUnwrap(fixture.session.handHistoryState.items.first?.id)
        fixture.session.requestDeleteHand(id: id)

        fixture.session.cancelHistoryDeletion()

        XCTAssertNil(fixture.session.handHistoryState.pendingDeletion)
        XCTAssertNil(
            HandHistoryDeletionPresentation.overlay(
                for: fixture.session.handHistoryState
            )
        )
    }

    @MainActor
    func testDeleteAllRequiresExplicitConfirmationAndPreservesCurrentSession() throws {
        let fixture = try HandHistoryAppFixture.withActiveReadySessionAndRecords()
        fixture.session.loadHandHistory()
        let cashSession = fixture.store.cashSession
        let balance = fixture.store.accountBalance
        let statistics = fixture.store.statistics

        fixture.session.requestDeleteAllHistory()

        XCTAssertEqual(fixture.store.handRecords().count, 3)
        XCTAssertEqual(fixture.session.handHistoryState.pendingDeletion, .all)

        try fixture.session.confirmHistoryDeletion()

        XCTAssertTrue(fixture.store.handRecords().isEmpty)
        XCTAssertTrue(fixture.session.handHistoryState.items.isEmpty)
        XCTAssertEqual(fixture.store.cashSession, cashSession)
        XCTAssertEqual(fixture.store.accountBalance, balance)
        XCTAssertEqual(fixture.store.statistics, statistics)
        XCTAssertNil(fixture.session.handHistoryState.pendingDeletion)
    }
}
