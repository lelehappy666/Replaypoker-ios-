import XCTest
@testable import RiverClub

final class BuyInTests: XCTestCase {
    func testBuyInClampsToTableRangeAndBalance() {
        var state = BuyInState(minimum: 2_000, maximum: 10_000, balance: 6_500)
        state.amount = 9_000
        state.normalize()
        XCTAssertEqual(state.amount, 6_500)
        XCTAssertTrue(state.canConfirm)
    }

    func testInsufficientBalanceCannotConfirm() {
        let state = BuyInState(minimum: 2_000, maximum: 10_000, balance: 1_500)
        XCTAssertFalse(state.canConfirm)
    }
}
