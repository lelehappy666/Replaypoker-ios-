import Testing
@testable import PokerCore

@Test func buildsSinglePot() throws {
    let commitments = try [0: 100, 1: 100, 2: 100].seatMap.chips

    let pots = try PotBuilder.build(commitments: commitments, folded: [])

    #expect(pots.map(\.amount.rawValue) == [300])
    #expect(pots[0].eligible == (try [0, 1, 2].seatSet))
}

@Test func buildsMainAndOneSidePot() throws {
    let commitments = try [0: 100, 1: 300, 2: 300].seatMap.chips

    let pots = try PotBuilder.build(commitments: commitments, folded: [])

    #expect(pots.map(\.amount.rawValue) == [300, 400])
    #expect(pots[0].eligible == (try [0, 1, 2].seatSet))
    #expect(pots[1].eligible == (try [1, 2].seatSet))
}

@Test func buildsMainAndTwoSidePots() throws {
    let commitments = try [0: 100, 1: 300, 2: 500, 3: 500].seatMap.chips
    let folded = try [3].seatSet

    let pots = try PotBuilder.build(commitments: commitments, folded: folded)

    #expect(pots.map(\.amount.rawValue) == [400, 600, 400])
    #expect(pots[0].eligible == (try [0, 1, 2].seatSet))
    #expect(pots[1].eligible == (try [1, 2].seatSet))
    #expect(pots[2].eligible == (try [2].seatSet))
}

@Test func buildsMainAndThreeSidePots() throws {
    let commitments = try [0: 100, 2: 300, 5: 500, 7: 700].seatMap.chips

    let pots = try PotBuilder.build(commitments: commitments, folded: [])

    #expect(pots.map(\.amount.rawValue) == [400, 600, 400, 200])
    #expect(pots[0].eligible == (try [0, 2, 5, 7].seatSet))
    #expect(pots[1].eligible == (try [2, 5, 7].seatSet))
    #expect(pots[2].eligible == (try [5, 7].seatSet))
    #expect(pots[3].eligible == (try [7].seatSet))
}

@Test func foldedCommitmentCountsTowardAmountButNotEligibility() throws {
    let commitments = try [0: 100, 1: 100, 2: 100].seatMap.chips

    let pots = try PotBuilder.build(
        commitments: commitments,
        folded: try [1].seatSet
    )

    #expect(pots.map(\.amount.rawValue) == [300])
    #expect(pots[0].eligible == (try [0, 2].seatSet))
}

@Test func ignoresZeroCommitments() throws {
    let commitments = try [0: 0, 1: 100, 2: 100].seatMap.chips

    let pots = try PotBuilder.build(commitments: commitments, folded: [])

    #expect(pots.map(\.amount.rawValue) == [200])
    #expect(pots[0].eligible == (try [1, 2].seatSet))
}

@Test func awardsPotWithSingleEligibleSeat() throws {
    let pot = Pot(amount: try Chips(500), eligible: try [4].seatSet)
    let ranks = try Fixtures.tiedRanks([4])

    let awards = try PotBuilder.awards(for: [pot], ranks: ranks, dealer: SeatID(8))

    #expect(awards == [try SeatID(4): try Chips(500)])
}

@Test func splitsPotBetweenEqualRanks() throws {
    let pot = Pot(amount: try Chips(100), eligible: try [0, 2].seatSet)

    let awards = try PotBuilder.awards(
        for: [pot],
        ranks: Fixtures.tiedRanks([0, 2]),
        dealer: SeatID(8)
    )

    #expect(awards == [try SeatID(0): try Chips(50), try SeatID(2): try Chips(50)])
}

@Test func oddChipMovesClockwiseFromDealerAcrossSparseSeats() throws {
    let pot = Pot(amount: try Chips(101), eligible: try [0, 2].seatSet)

    let awards = try PotBuilder.awards(
        for: [pot],
        ranks: Fixtures.tiedRanks([0, 2]),
        dealer: SeatID(8)
    )

    #expect(awards[try SeatID(0)]?.rawValue == 51)
    #expect(awards[try SeatID(2)]?.rawValue == 50)
}

@Test func awardsMultipleOddChipsClockwiseAndDealerLast() throws {
    let pot = Pot(amount: try Chips(11), eligible: try [0, 3, 6, 8].seatSet)

    let awards = try PotBuilder.awards(
        for: [pot],
        ranks: Fixtures.tiedRanks([0, 3, 6, 8]),
        dealer: SeatID(6)
    )

    #expect(awards[try SeatID(8)]?.rawValue == 3)
    #expect(awards[try SeatID(0)]?.rawValue == 3)
    #expect(awards[try SeatID(3)]?.rawValue == 3)
    #expect(awards[try SeatID(6)]?.rawValue == 2)
}

@Test func eachSidePotChoosesItsOwnWinners() throws {
    let pots = [
        Pot(amount: try Chips(400), eligible: try [0, 1, 2].seatSet),
        Pot(amount: try Chips(300), eligible: try [1, 2].seatSet),
        Pot(amount: try Chips(200), eligible: try [2].seatSet),
    ]
    let ranks = [
        try SeatID(0): HandRank(category: .straight, tieBreak: [10]),
        try SeatID(1): HandRank(category: .threeOfAKind, tieBreak: [14, 13, 12]),
        try SeatID(2): HandRank(category: .twoPair, tieBreak: [14, 13, 12]),
    ]

    let awards = try PotBuilder.awards(for: pots, ranks: ranks, dealer: SeatID(8))

    #expect(awards == [
        try SeatID(0): try Chips(400),
        try SeatID(1): try Chips(300),
        try SeatID(2): try Chips(200),
    ])
}

@Test func rejectsMissingRank() throws {
    let pot = Pot(amount: try Chips(100), eligible: try [0, 1].seatSet)

    #expect(throws: PokerRuleError.invalidState("missing hand rank")) {
        try PotBuilder.awards(
            for: [pot],
            ranks: Fixtures.tiedRanks([0]),
            dealer: SeatID(8)
        )
    }
}

@Test func rejectsEmptyEligibleSet() throws {
    let pot = Pot(amount: try Chips(100), eligible: [])

    #expect(throws: PokerRuleError.invalidState("pot has no eligible seats")) {
        try PotBuilder.awards(for: [pot], ranks: [:], dealer: SeatID(8))
    }
}

@Test func rejectsLayerWithoutEligibleSeat() throws {
    let commitments = try [0: 100, 1: 200].seatMap.chips

    #expect(throws: PokerRuleError.invalidState("pot has no eligible seats")) {
        try PotBuilder.build(commitments: commitments, folded: try [0, 1].seatSet)
    }
}

@Test func rejectsLayerMultiplicationOverflow() throws {
    let commitments = try [0: Int.max, 1: Int.max].seatMap.chips

    #expect(throws: PokerRuleError.invalidState("chip arithmetic overflow")) {
        try PotBuilder.build(commitments: commitments, folded: [])
    }
}

@Test func rejectsCommitmentTotalOverflow() throws {
    let commitments = try [0: Int.max, 1: 1].seatMap.chips

    #expect(throws: PokerRuleError.invalidState("chip arithmetic overflow")) {
        try PotBuilder.build(commitments: commitments, folded: [])
    }
}

@Test func rejectsPotTotalOverflowWhenAwarding() throws {
    let pots = [
        Pot(amount: try Chips(Int.max), eligible: try [0].seatSet),
        Pot(amount: try Chips(1), eligible: try [1].seatSet),
    ]
    let ranks = try Fixtures.tiedRanks([0, 1])

    #expect(throws: PokerRuleError.invalidState("chip arithmetic overflow")) {
        try PotBuilder.awards(for: pots, ranks: ranks, dealer: SeatID(8))
    }
}

@Test func preservesTotalCommitmentsAndAwards() throws {
    let commitments = try [0: 100, 1: 301, 2: 500, 3: 500].seatMap.chips
    let folded = try [3].seatSet
    let pots = try PotBuilder.build(commitments: commitments, folded: folded)
    let ranks = [
        try SeatID(0): HandRank(category: .straight, tieBreak: [10]),
        try SeatID(1): HandRank(category: .straight, tieBreak: [10]),
        try SeatID(2): HandRank(category: .twoPair, tieBreak: [14, 13, 12]),
    ]

    let awards = try PotBuilder.awards(for: pots, ranks: ranks, dealer: SeatID(8))

    #expect(pots.reduce(0) { $0 + $1.amount.rawValue } == 1_401)
    #expect(awards.values.reduce(0) { $0 + $1.rawValue } == 1_401)
}
