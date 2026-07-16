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

    func testListItemExposesBlindsExactCompletionTimeAndAllocatedPotTotal() throws {
        let record = try makeHistoryRecord(
            archiveMetadata: try makePresentationArchiveMetadata()
        )
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))

        let item = try HandHistoryPresentation.listItem(
            from: record,
            timeZone: timeZone
        )

        XCTAssertEqual(item.blindsText, "小盲 50 · 大盲 100")
        XCTAssertEqual(item.completedAtText, "1970-01-01 08:17:40")
        XCTAssertEqual(
            item.allocatedPotTotal,
            try Chips(record.record.awards.values.reduce(0) { $0 + $1.rawValue })
        )
        XCTAssertEqual(
            item.allocatedPotTotalText,
            "已分配底池 \(item.allocatedPotTotal.rawValue.formatted())"
        )
    }

    func testDetailExposesBlindsExactCompletionTimeAndFormattedSeatStacks() throws {
        let record = try makeHistoryRecord(
            archiveMetadata: try makePresentationArchiveMetadata()
        )
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))

        let detail = try HandHistoryPresentation.detail(
            from: record,
            timeZone: timeZone
        )
        let seat = try XCTUnwrap(detail.seats.first)

        XCTAssertEqual(detail.blindsText, "小盲 50 · 大盲 100")
        XCTAssertEqual(detail.completedAtText, "1970-01-01 08:17:40")
        XCTAssertEqual(
            seat.stackSummaryText,
            "起始 \(seat.startingStack.rawValue.formatted()) · 最终 \(seat.finalStack.rawValue.formatted()) · 净变化 \(seat.chipDeltaText)"
        )
    }

    func testPotWinnersAndUncalledReturnsUseFrozenPlayerNames() throws {
        let record = try makeHistoryRecord(
            archiveMetadata: try makePresentationArchiveMetadata()
        )
        let returnRecord = try makeUncalledReturnHistoryRecord()

        let detail = try HandHistoryPresentation.detail(from: record)
        let returnDetail = try HandHistoryPresentation.detail(from: returnRecord)

        XCTAssertTrue(
            detail.pots
                .flatMap(\.winnerAmounts)
                .allSatisfy { $0.displayName.hasPrefix("玩家") }
        )
        XCTAssertFalse(returnDetail.uncalledReturns.isEmpty)
        XCTAssertTrue(
            returnDetail.uncalledReturns.allSatisfy {
                $0.displayName.hasPrefix("玩家")
            }
        )
    }

    func testLegacyListDeltaIsUnknownEvenWhenSeatEightHasNonzeroDelta() throws {
        let record = try makeHistoryRecord(
            humanSeat: SeatID(rawValue: 8)!,
            archiveMetadata: nil
        )
        XCTAssertNotEqual(record.record.chipDeltas[SeatID(rawValue: 8)!], 0)

        let item = try HandHistoryPresentation.listItem(from: record)

        XCTAssertNil(item.humanChipDelta)
        XCTAssertEqual(item.humanChipDeltaText, "未知（旧记录不可用）")
    }

    func testListAndDetailExposeOnlyCompletedPublicCardsAndReturns() throws {
        let record = try makeHistoryRecord(
            archiveMetadata: makePresentationArchiveMetadata()
        )

        let item = try HandHistoryPresentation.listItem(from: record)
        let detail = try HandHistoryPresentation.detail(from: record)

        XCTAssertEqual(item.communityCards, record.record.communityCards)
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: detail.uncalledReturns.map {
                    ($0.seatID, $0.amount)
                }
            ),
            record.record.uncalledReturns
        )
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

    func testCustomDatePolicyConvertsUserDateUsingTheCalendarTimeZone() throws {
        let instant = Date(timeIntervalSince1970: 1_768_498_200)
        var eastCalendar = Calendar(identifier: .gregorian)
        eastCalendar.timeZone = try XCTUnwrap(
            TimeZone(secondsFromGMT: 8 * 60 * 60)
        )
        var westCalendar = Calendar(identifier: .gregorian)
        westCalendar.timeZone = try XCTUnwrap(
            TimeZone(secondsFromGMT: -11 * 60 * 60)
        )

        XCTAssertEqual(
            try HandHistoryCustomDatePolicy.localDay(
                from: instant,
                calendar: eastCalendar
            ),
            try LocalDay("2026-01-16")
        )
        XCTAssertEqual(
            try HandHistoryCustomDatePolicy.localDay(
                from: instant,
                calendar: westCalendar
            ),
            try LocalDay("2026-01-15")
        )
    }

    func testStoredCustomLocalDayRoundTripsWithoutChangingItsNaturalDay() throws {
        let storedDay = try LocalDay("2026-07-16")
        for seconds in [-11 * 60 * 60, 14 * 60 * 60] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(
                TimeZone(secondsFromGMT: seconds)
            )

            let pickerDate = try HandHistoryCustomDatePolicy.date(
                for: storedDay,
                calendar: calendar
            )

            XCTAssertEqual(
                try HandHistoryCustomDatePolicy.localDay(
                    from: pickerDate,
                    calendar: calendar
                ),
                storedDay
            )
        }
    }

    func testCustomDatePolicyAlwaysUsesGregorianYearWithNonGregorianCalendars() throws {
        let instant = Date(timeIntervalSince1970: 1_768_498_200)
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))
        for identifier in [
            Calendar.Identifier.buddhist,
            Calendar.Identifier.islamicCivil,
        ] {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = timeZone

            XCTAssertEqual(
                try HandHistoryCustomDatePolicy.localDay(
                    from: instant,
                    calendar: calendar
                ),
                try LocalDay("2026-01-16")
            )
        }
    }

    func testStoredGregorianLocalDayRoundTripsThroughNonGregorianPickerCalendars() throws {
        let storedDay = try LocalDay("2026-07-16")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))
        for identifier in [
            Calendar.Identifier.buddhist,
            Calendar.Identifier.islamicCivil,
        ] {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = timeZone

            let pickerDate = try HandHistoryCustomDatePolicy.date(
                for: storedDay,
                calendar: calendar
            )

            XCTAssertEqual(
                try HandHistoryCustomDatePolicy.localDay(
                    from: pickerDate,
                    calendar: calendar
                ),
                storedDay
            )
        }
    }
}
