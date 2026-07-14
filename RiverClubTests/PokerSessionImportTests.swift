import XCTest
import PokerSession
import PokerCore

final class PokerSessionImportTests: XCTestCase {
    func testApprovedEconomyConstantsAreAvailableToApplication() throws {
        XCTAssertEqual(SessionEconomy.initialBalance, try Chips(128_500))
    }
}
