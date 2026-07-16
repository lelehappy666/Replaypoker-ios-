import PokerCore
import Testing
@testable import PokerBot

@Test func 默认下注尺度使用百分之六十六点五底池而不是半副筹码() throws {
    let target = try BotBetSizing.target(
        minimum: try Chips(400),
        maximum: try Chips(20_000),
        currentCommitment: try Chips(0),
        pot: try Chips(1_000),
        sizing: 50
    )

    #expect(target == (try Chips(665)))
}

@Test func 下注尺度始终受最小值和最大值约束() throws {
    #expect(
        try BotBetSizing.target(
            minimum: try Chips(800),
            maximum: try Chips(20_000),
            currentCommitment: try Chips(100),
            pot: try Chips(300),
            sizing: 0
        ) == (try Chips(800))
    )
    #expect(
        try BotBetSizing.target(
            minimum: try Chips(400),
            maximum: try Chips(900),
            currentCommitment: try Chips(100),
            pot: try Chips(2_000),
            sizing: 100
        ) == (try Chips(900))
    )
}

@Test func 深筹码中等牌力没有全下资格() {
    #expect(
        !BotAllInEligibility.isEligible(
            strengthBasisPoints: 6_000,
            simulatedEquityBasisPoints: nil,
            effectiveStackBigBlinds: 100,
            potOddsBasisPoints: 2_500,
            model: .balanced,
            forcedShortCall: false
        )
    )
}

@Test func 十二个大盲强牌和被迫短跟注保留合理全下() {
    #expect(
        BotAllInEligibility.isEligible(
            strengthBasisPoints: 7_000,
            simulatedEquityBasisPoints: nil,
            effectiveStackBigBlinds: 12,
            potOddsBasisPoints: 3_000,
            model: .balanced,
            forcedShortCall: false
        )
    )
    #expect(
        BotAllInEligibility.isEligible(
            strengthBasisPoints: 2_000,
            simulatedEquityBasisPoints: nil,
            effectiveStackBigBlinds: 100,
            potOddsBasisPoints: 8_000,
            model: .conservative,
            forcedShortCall: true
        )
    )
}

@Test func 激进模型仍需同时满足牌力赔率和有效筹码条件() {
    #expect(
        BotAllInEligibility.isEligible(
            strengthBasisPoints: 7_500,
            simulatedEquityBasisPoints: nil,
            effectiveStackBigBlinds: 30,
            potOddsBasisPoints: 4_000,
            model: .aggressive,
            forcedShortCall: false
        )
    )
    #expect(
        !BotAllInEligibility.isEligible(
            strengthBasisPoints: 7_499,
            simulatedEquityBasisPoints: nil,
            effectiveStackBigBlinds: 30,
            potOddsBasisPoints: 4_000,
            model: .aggressive,
            forcedShortCall: false
        )
    )
}
