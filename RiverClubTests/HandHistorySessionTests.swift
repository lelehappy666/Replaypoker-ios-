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
}
