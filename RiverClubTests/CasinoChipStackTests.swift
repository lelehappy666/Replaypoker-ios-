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

    func testStandardAmountsUseTheSpecifiedCasinoDenominationsAndColors() {
        XCTAssertEqual(CasinoChipDenomination.one.rawValue, 1)
        XCTAssertEqual(CasinoChipDenomination.one.semanticColorName, "white")
        XCTAssertEqual(CasinoChipDenomination.five.rawValue, 5)
        XCTAssertEqual(CasinoChipDenomination.five.semanticColorName, "red")
        XCTAssertEqual(CasinoChipDenomination.twentyFive.rawValue, 25)
        XCTAssertEqual(CasinoChipDenomination.twentyFive.semanticColorName, "green")
        XCTAssertEqual(CasinoChipDenomination.oneHundred.rawValue, 100)
        XCTAssertEqual(CasinoChipDenomination.oneHundred.semanticColorName, "black")
        XCTAssertEqual(CasinoChipDenomination.fiveHundred.rawValue, 500)
        XCTAssertEqual(CasinoChipDenomination.fiveHundred.semanticColorName, "purple")
        XCTAssertEqual(CasinoChipDenomination.oneThousand.rawValue, 1_000)
        XCTAssertEqual(CasinoChipDenomination.oneThousand.semanticColorName, "orange")
    }

    func testNonPositiveAmountsAndNonPositiveLimitsProduceNoVisualChips() {
        XCTAssertEqual(CasinoChipBreakdown.make(amount: 0, maximumVisibleChips: 8), [])
        XCTAssertEqual(CasinoChipBreakdown.make(amount: -10, maximumVisibleChips: 8), [])
        XCTAssertEqual(CasinoChipBreakdown.make(amount: 600, maximumVisibleChips: 0), [])
        XCTAssertEqual(CasinoChipBreakdown.make(amount: 600, maximumVisibleChips: -1), [])
    }

    func testNonStandardAmountKeepsExactGreedyValueWhenItFitsRequestedAndSupportedLimits() {
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

    func testFourteenNinetyNineKeepsGreedyPrefixAtOneAndTwoChipLimits() {
        XCTAssertEqual(
            CasinoChipBreakdown.make(amount: 1_499, maximumVisibleChips: 1),
            [.oneThousand]
        )
        XCTAssertEqual(
            CasinoChipBreakdown.make(amount: 1_499, maximumVisibleChips: 2),
            [.oneThousand, .fiveHundred]
        )
    }

    func testMaximumIntegerAmountCompletesWithinTheVisibleLimit() {
        let chips = CasinoChipBreakdown.make(amount: .max, maximumVisibleChips: 4)

        XCTAssertEqual(chips, [.oneThousand, .oneThousand, .oneThousand, .oneThousand])
    }

    func testMaximumIntegerInputsStayWithinThePublishedVisualSafetyLimit() {
        let chips = CasinoChipBreakdown.make(amount: .max, maximumVisibleChips: .max)

        XCTAssertLessThanOrEqual(chips.count, CasinoChipBreakdown.maximumSupportedVisibleChips)
        XCTAssertTrue(chips.allSatisfy { $0 == .oneThousand })
    }

    func testRequestedLimitAbovePublishedSafetyLimitUsesThePublishedLimit() {
        let chips = CasinoChipBreakdown.make(amount: 70_000, maximumVisibleChips: 100)

        XCTAssertEqual(CasinoChipBreakdown.maximumSupportedVisibleChips, 64)
        XCTAssertEqual(chips.count, CasinoChipBreakdown.maximumSupportedVisibleChips)
        XCTAssertTrue(chips.allSatisfy { $0 == .oneThousand })
    }

    func testDisplayAmountUsesFixedThousandsSeparatorsWithoutCurrencySymbol() {
        XCTAssertEqual(CasinoChipAmountPresentation.text(for: 88_500), "88,500")
        XCTAssertEqual(CasinoChipAmountPresentation.text(for: 12_000), "12,000")
        XCTAssertNotEqual(
            CasinoChipAmountPresentation.text(for: 88_500),
            CasinoChipAmountPresentation.text(for: 12_000)
        )
    }
}
