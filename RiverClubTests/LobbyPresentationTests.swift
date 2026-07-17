import XCTest
@testable import RiverClub

final class LobbyPresentationTests: XCTestCase {
    func testEntertainmentAmountsUseDollarSymbolButBlindLevelsDoNot() {
        XCTAssertEqual(EntertainmentAmountFormatter.string(88_500), "$88,500")
        XCTAssertEqual(PokerTablePresentation.blinds(small: 100, big: 200), "100 / 200")
    }

    func testEntertainmentAmountsUseFixedEnglishGroupingInsteadOfCurrentLocale() {
        XCTAssertEqual(EntertainmentAmountFormatter.string(88_500), "$88,500")
    }

    func testEntertainmentAmountsPlaceNegativeSignBeforeDollarSymbol() {
        XCTAssertEqual(EntertainmentAmountFormatter.string(-1_234), "-$1,234")
    }

    func testEntertainmentAmountsFormatIntegerBoundsWithoutOverflow() {
        XCTAssertEqual(
            EntertainmentAmountFormatter.string(Int.max),
            "$9,223,372,036,854,775,807"
        )
        XCTAssertEqual(
            EntertainmentAmountFormatter.string(Int.min),
            "-$9,223,372,036,854,775,808"
        )
    }

    func testLobbyPreviewIsStableAndUniquePerTable() {
        let tableID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

        let first = RobotIdentityCatalog.preview(for: tableID, count: 6)
        let second = RobotIdentityCatalog.preview(for: tableID, count: 6)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 6)
        XCTAssertEqual(Set(first.map(\.id)).count, 6)
    }
}
