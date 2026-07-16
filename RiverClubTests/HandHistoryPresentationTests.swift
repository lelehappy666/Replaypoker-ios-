import Foundation
import PokerCore
import PokerSession
import XCTest
@testable import RiverClub

final class HandHistoryPresentationTests: XCTestCase {
    func testFinalResultIncludesFoldedHoleCardsAndHumanDelta() throws {
        let record = try makeHistoryRecord(
            foldedSeat: SeatID(rawValue: 3)!,
            humanSeat: SeatID(rawValue: 0)!,
            archiveMetadata: makePresentationArchiveMetadata()
        )

        let detail = try HandHistoryPresentation.detail(from: record)

        XCTAssertEqual(detail.seats.count, 9)
        XCTAssertEqual(detail.seats.first { $0.id.rawValue == 3 }?.cards.count, 2)
        XCTAssertEqual(detail.seats.first { $0.id.rawValue == 3 }?.status, .folded)
        XCTAssertEqual(
            detail.seats.first { $0.id.rawValue == 0 }?.chipDelta,
            record.record.chipDeltas[SeatID(rawValue: 0)!]
        )
    }

    func testLegacyRecordUsesStableFallbackNames() throws {
        let record = try makeHistoryRecord(archiveMetadata: nil)

        let detail = try HandHistoryPresentation.detail(from: record)

        XCTAssertEqual(detail.tableName, "牌桌 \(record.table.rawValue)")
        XCTAssertEqual(detail.seats.map(\.displayName).first, "座位 1")
    }

    func testPotRowsRebuildPerPotWinnersAndOddChipAmounts() throws {
        let record = try makeMultiPotHistoryRecord()

        let detail = try HandHistoryPresentation.detail(from: record)

        XCTAssertEqual(detail.pots.count, record.record.pots.count)
        XCTAssertEqual(
            detail.pots.flatMap(\.amounts).reduce(0) { $0 + $1.value.rawValue },
            record.record.awards.values.reduce(0) { $0 + $1.rawValue }
        )
        for (index, pot) in record.record.pots.enumerated() {
            XCTAssertEqual(
                detail.pots[index].amounts,
                try PotBuilder.awards(
                    for: [pot],
                    ranks: record.record.handRanksBySeat,
                    dealer: record.record.config.dealer
                )
            )
        }
        XCTAssertTrue(zip(record.record.pots, detail.pots).contains { pot, row in
            row.amounts.count > 1 && pot.amount.rawValue % row.amounts.count != 0
        })
    }

    func testEarlyFoldPotDoesNotRequireSyntheticRanks() throws {
        let record = try makeHistoryRecord(
            foldedSeat: SeatID(rawValue: 3)!,
            archiveMetadata: makePresentationArchiveMetadata()
        )

        XCTAssertTrue(record.record.handRanksBySeat.isEmpty)
        let detail = try HandHistoryPresentation.detail(from: record)

        XCTAssertEqual(detail.pots.count, record.record.pots.count)
        for (index, pot) in record.record.pots.enumerated() {
            XCTAssertEqual(pot.eligible.count, 1)
            XCTAssertEqual(
                detail.pots[index].amounts.values.reduce(0) { $0 + $1.rawValue },
                pot.amount.rawValue
            )
        }
    }

    func testListItemUsesFrozenNamesAndHumanDelta() throws {
        let metadata = try makePresentationArchiveMetadata()
        let record = try makeHistoryRecord(
            humanSeat: metadata.humanSeat,
            archiveMetadata: metadata
        )

        let item = try HandHistoryPresentation.listItem(from: record)

        XCTAssertEqual(item.id, record.id)
        XCTAssertEqual(item.tableName, metadata.tableDisplayName)
        XCTAssertEqual(item.humanChipDelta, record.record.chipDeltas[metadata.humanSeat])
    }

    func testDateSelectionsMapToExactStoredLocalDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 14 * 60 * 60)!
        let today = try LocalDay("2026-07-16")
        let table = try TableID("jade")

        let all = try HandHistoryPresentation.storeFilter(
            filters: HandHistoryFilters(table: table, dateSelection: .all),
            today: today,
            calendar: calendar
        )
        let exactToday = try HandHistoryPresentation.storeFilter(
            filters: HandHistoryFilters(table: table, dateSelection: .today),
            today: today,
            calendar: calendar
        )
        let customDay = try LocalDay("2026-06-30")
        let custom = try HandHistoryPresentation.storeFilter(
            filters: HandHistoryFilters(table: table, dateSelection: .custom(customDay)),
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(all, HandRecordFilter(table: table))
        XCTAssertEqual(exactToday, HandRecordFilter(table: table, localDay: today))
        XCTAssertEqual(custom, HandRecordFilter(table: table, localDay: customDay))
    }

    func testLastSevenDaysUsesInclusiveNaturalDayRangeAcrossMonthBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -11 * 60 * 60)!
        let today = try LocalDay("2026-03-03")

        let filter = try HandHistoryPresentation.storeFilter(
            filters: HandHistoryFilters(dateSelection: .lastSevenDays),
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(filter.dateRange?.first, try LocalDay("2026-02-25"))
        XCTAssertEqual(filter.dateRange?.last, today)
        XCTAssertNil(filter.localDay)
    }
}
