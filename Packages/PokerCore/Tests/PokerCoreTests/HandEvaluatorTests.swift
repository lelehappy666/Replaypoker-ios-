import Testing
@testable import PokerCore

struct CategoryCase: Sendable {
    let source: String
    let category: HandCategory
}

@Test(arguments: [
    CategoryCase(source: "As Ks Qs Js Ts 2d 3c", category: .straightFlush),
    CategoryCase(source: "Ah Ad Ac As Kd 2c 3h", category: .fourOfAKind),
    CategoryCase(source: "Kh Kd Kc 2s 2d 8c 9h", category: .fullHouse),
    CategoryCase(source: "As 9s 7s 4s 2s Kd Qh", category: .flush),
    CategoryCase(source: "5s 4d 3c 2h As Kd Qh", category: .straight),
    CategoryCase(source: "Qh Qd Qc 9s 7d 4c 2h", category: .threeOfAKind),
    CategoryCase(source: "Jh Jd 8c 8s Ad 4c 2h", category: .twoPair),
    CategoryCase(source: "Th Td As 8c 6d 4s 2h", category: .onePair),
    CategoryCase(source: "As Qd 9c 7h 4s 3d 2c", category: .highCard),
]) func recognizesCategories(example: CategoryCase) throws {
    #expect(try HandEvaluator.best(of: Cards.parse(example.source)).category == example.category)
}

@Test func recognizesRoyalFlushAsStraightFlush() throws {
    let rank = try HandEvaluator.best(of: Cards.parse("As Ks Qs Js Ts"))

    #expect(rank.category == .straightFlush)
    #expect(rank.tieBreak == [14])
}

@Test func comparesPairKickersLexicographically() throws {
    let queenSecondKicker = try HandEvaluator.best(of: Cards.parse("Ah Ad Ks Qc 9s 3d 2c"))
    let jackSecondKicker = try HandEvaluator.best(of: Cards.parse("Ah Ad Ks Jc 9s 3d 2c"))

    #expect(queenSecondKicker > jackSecondKicker)
}

@Test func producesRequiredTieBreakOrderForMadeHands() throws {
    #expect(try HandEvaluator.best(of: Cards.parse("Ah Ad Ac As Kd 2c 3h")).tieBreak == [14, 13])
    #expect(try HandEvaluator.best(of: Cards.parse("Kh Kd Kc 2s 2d 8c 9h")).tieBreak == [13, 2])
    #expect(try HandEvaluator.best(of: Cards.parse("Qh Qd Qc As 9d 4c 2h")).tieBreak == [12, 14, 9])
    #expect(try HandEvaluator.best(of: Cards.parse("Jh Jd 8c 8s Ad 4c 2h")).tieBreak == [11, 8, 14])
    #expect(try HandEvaluator.best(of: Cards.parse("Th Td As 8c 6d 4s 2h")).tieBreak == [10, 14, 8, 6])
}

@Test func producesDescendingRanksForFlushAndHighCard() throws {
    #expect(try HandEvaluator.best(of: Cards.parse("As 9s 7s 4s 2s Kd Qh")).tieBreak == [14, 9, 7, 4, 2])
    #expect(try HandEvaluator.best(of: Cards.parse("As Qd 9c 7h 4s 3d 2c")).tieBreak == [14, 12, 9, 7, 4])
}

@Test func wheelStraightRanksAsFiveHigh() throws {
    let wheel = try HandEvaluator.best(of: Cards.parse("As 2d 3c 4h 5s Kd Qh"))

    #expect(wheel.category == .straight)
    #expect(wheel.tieBreak == [5])
}

@Test func choosesBestFiveCardsFromSeven() throws {
    let rank = try HandEvaluator.best(of: Cards.parse("Ah Ad Ac Ks Kd Kh 2c"))

    #expect(rank.category == .fullHouse)
    #expect(rank.tieBreak == [14, 13])
}

@Test func choosesBestFiveCardsFromSix() throws {
    let rank = try HandEvaluator.best(of: Cards.parse("Ah Ad Ac Ks Kd 2c"))

    #expect(rank == HandRank(category: .fullHouse, tieBreak: [14, 13]))
}

@Test func comparesTwoPairByLowPairThenKicker() throws {
    let higherLowPair = try HandEvaluator.best(of: Cards.parse("Ah Ad Qs Qc 2s 3d 4c"))
    let lowerLowPair = try HandEvaluator.best(of: Cards.parse("Ah Ad Js Jc Ks 3d 4c"))
    let higherKicker = try HandEvaluator.best(of: Cards.parse("Ah Ad Qs Qc Ks 3d 4c"))

    #expect(higherLowPair > lowerLowPair)
    #expect(higherKicker > higherLowPair)
}

@Test func comparesFlushByDeepKicker() throws {
    let fiveHighFourthKicker = try HandEvaluator.best(of: Cards.parse("As Qs 9s 5s 2s Kd Jh"))
    let fourHighFourthKicker = try HandEvaluator.best(of: Cards.parse("As Qs 9s 4s 3s Kd Jh"))

    #expect(fiveHighFourthKicker > fourHighFourthKicker)
}

@Test func categoryOutranksTieBreakValues() {
    let pair = HandRank(category: .onePair, tieBreak: [2, 3, 4, 5])
    let aceHigh = HandRank(category: .highCard, tieBreak: [14, 13, 12, 11, 9])

    #expect(pair > aceHigh)
}

@Test(arguments: [
    "As Ks Qs Js",
    "As Ks Qs Js Ts 9d 8c 7h",
]) func rejectsWrongCardCounts(source: String) throws {
    #expect(throws: PokerRuleError.invalidCards) {
        try HandEvaluator.best(of: Cards.parse(source))
    }
}

@Test func rejectsDuplicateCards() throws {
    #expect(throws: PokerRuleError.invalidCards) {
        try HandEvaluator.best(of: Cards.parse("As As Qs Js Ts 9d 8c"))
    }
}
