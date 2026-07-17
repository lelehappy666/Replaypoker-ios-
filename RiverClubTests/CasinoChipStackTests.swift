import XCTest
@testable import RiverClub

@MainActor
final class CasinoChipStackTests: XCTestCase {
    func testSixHundredUsesPurpleAndBlackCasinoChips() {
        XCTAssertEqual(
            CasinoChipBreakdown.make(amount: 600, maximumVisibleChips: 8),
            [.fiveHundred, .oneHundred]
        )
    }

    func testLargePotKeepsVisualChipCountBounded() {
        XCTAssertLessThanOrEqual(
            CasinoChipBreakdown.make(amount: 88_500, maximumVisibleChips: 12).count,
            12
        )
    }

    func testStandardAmountsUseTheSpecifiedCasinoDenominations() {
        XCTAssertEqual(CasinoChipDenomination.one.rawValue, 1)
        XCTAssertEqual(CasinoChipDenomination.five.rawValue, 5)
        XCTAssertEqual(CasinoChipDenomination.twentyFive.rawValue, 25)
        XCTAssertEqual(CasinoChipDenomination.oneHundred.rawValue, 100)
        XCTAssertEqual(CasinoChipDenomination.fiveHundred.rawValue, 500)
        XCTAssertEqual(CasinoChipDenomination.oneThousand.rawValue, 1_000)
    }

    func testNonPositiveAmountsAndNonPositiveLimitsProduceNoVisualChips() {
        XCTAssertEqual(CasinoChipBreakdown.make(amount: 0, maximumVisibleChips: 8), [])
        XCTAssertEqual(CasinoChipBreakdown.make(amount: -10, maximumVisibleChips: 8), [])
        XCTAssertEqual(CasinoChipBreakdown.make(amount: 600, maximumVisibleChips: 0), [])
        XCTAssertEqual(CasinoChipBreakdown.make(amount: 600, maximumVisibleChips: -1), [])
    }

    func testNonStandardAmountKeepsExactGreedyValueWhenItFitsTheLimit() {
        let chips = CasinoChipBreakdown.make(amount: 1_043, maximumVisibleChips: 8)

        XCTAssertEqual(chips, [.oneThousand, .twentyFive, .five, .five, .five, .one, .one, .one])
        XCTAssertEqual(chips.reduce(0) { $0 + $1.rawValue }, 1_043)
    }

    func testCompressionUsesHighestDenominationFirstWithoutClaimingExactValue() {
        XCTAssertEqual(
            CasinoChipBreakdown.make(amount: 88_500, maximumVisibleChips: 3),
            [.oneThousand, .oneThousand, .oneThousand]
        )
    }

    func testMaximumIntegerAmountCompletesWithinTheVisibleLimit() {
        let chips = CasinoChipBreakdown.make(amount: .max, maximumVisibleChips: 4)

        XCTAssertEqual(chips, [.oneThousand, .oneThousand, .oneThousand, .oneThousand])
    }

    func testMaximumIntegerInputsStayWithinTheInternalVisualSafetyLimit() {
        let chips = CasinoChipBreakdown.make(amount: .max, maximumVisibleChips: .max)

        XCTAssertLessThanOrEqual(chips.count, 64)
        XCTAssertTrue(chips.allSatisfy { $0 == .oneThousand })
    }
}
