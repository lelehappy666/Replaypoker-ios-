import XCTest
@testable import RiverClub

final class LobbyPresentationTests: XCTestCase {
    func testEntertainmentAmountsUseDollarSymbolButBlindLevelsDoNot() {
        XCTAssertEqual(EntertainmentAmountFormatter.string(88_500), "$88,500")
        XCTAssertEqual(PokerTablePresentation.blinds(small: 100, big: 200), "100 / 200")
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
