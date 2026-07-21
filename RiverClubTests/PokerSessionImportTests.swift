import XCTest
import PokerCoordinator
import PokerSession
import PokerCore

final class PokerSessionImportTests: XCTestCase {
    func testApprovedEconomyConstantsAreAvailableToApplication() throws {
        XCTAssertEqual(SessionEconomy.initialBalance, try Chips(1_000_000))
    }

    func testCoordinatorPublicStateIsAvailableToApplication() {
        XCTAssertEqual(TableFlowPhase.awaitingNextHand.rawValue, "awaitingNextHand")
    }
}
