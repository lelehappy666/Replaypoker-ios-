import XCTest
import PokerCoordinator
import PokerSession
import PokerCore

final class PokerSessionImportTests: XCTestCase {
    func testApprovedEconomyConstantsAreAvailableToApplication() throws {
        XCTAssertEqual(SessionEconomy.initialBalance, try Chips(128_500))
    }

    func testCoordinatorPublicStateIsAvailableToApplication() {
        XCTAssertEqual(TableFlowPhase.awaitingNextHand.rawValue, "awaitingNextHand")
    }
}
