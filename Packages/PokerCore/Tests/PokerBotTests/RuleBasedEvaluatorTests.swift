import Foundation
import PokerCore
import Testing
@testable import PokerBot

@Test func 简单与标准难度使用不同公开特征() throws {
    let observation = try makeStrategyObservation(
        ownCards: #"[{"rank":14,"suit":3},{"rank":13,"suit":3}]"#,
        communityCards: #"[{"rank":2,"suit":0},{"rank":7,"suit":1},{"rank":10,"suit":2}]"#
    )

    let simple = try RuleBasedEvaluator().evaluate(
        observation,
        settings: makeSettings(difficulty: .easy)
    )
    let standard = try RuleBasedEvaluator().evaluate(
        observation,
        settings: makeSettings(difficulty: .standard)
    )

    #expect(simple.features.contains(.madeHandStrength))
    #expect(simple.features.contains(.position))
    #expect(!simple.features.contains(.potOdds))
    #expect(!simple.features.contains(.boardTexture))
    #expect(standard.features.contains(.potOdds))
    #expect(standard.features.contains(.boardTexture))
    #expect(standard.features.contains(.effectiveStack))
}

@Test func 困难难度增加对手范围和公开行动历史() throws {
    let observation = try makeStrategyObservation()
    let result = try RuleBasedEvaluator().evaluate(
        observation,
        settings: makeSettings(difficulty: .hard)
    )

    #expect(result.features.contains(.opponentRange))
    #expect(result.features.contains(.publicActionHistory))
}

@Test func 强起手牌评分高于弱起手牌() throws {
    let aces = try makeStrategyObservation(
        ownCards: #"[{"rank":14,"suit":3},{"rank":14,"suit":2}]"#
    )
    let sevenTwo = try makeStrategyObservation(
        ownCards: #"[{"rank":7,"suit":3},{"rank":2,"suit":1}]"#
    )
    let evaluator = RuleBasedEvaluator()
    let settings = makeSettings(difficulty: .standard)

    #expect(
        try evaluator.evaluate(aces, settings: settings).strengthBasisPoints
            > evaluator.evaluate(sevenTwo, settings: settings).strengthBasisPoints
    )
}

@Test func 湿润牌面纹理评分高于干燥牌面() throws {
    let wet = try makeStrategyObservation(
        communityCards: #"[{"rank":9,"suit":2},{"rank":10,"suit":2},{"rank":11,"suit":2}]"#
    )
    let dry = try makeStrategyObservation(
        communityCards: #"[{"rank":2,"suit":0},{"rank":7,"suit":1},{"rank":13,"suit":2}]"#
    )
    let evaluator = RuleBasedEvaluator()
    let settings = makeSettings(difficulty: .standard)

    let wetTexture = try #require(
        evaluator.evaluate(wet, settings: settings).boardTextureBasisPoints
    )
    let dryTexture = try #require(
        evaluator.evaluate(dry, settings: settings).boardTextureBasisPoints
    )
    #expect(wetTexture > dryTexture)
}

@Test func 位置评分不会因对手本手弃牌而变化() throws {
    let beforeFold = try makeStrategyObservation(seatTwoHasFolded: false)
    let afterFold = try makeStrategyObservation(seatTwoHasFolded: true)
    let evaluator = RuleBasedEvaluator()
    let settings = makeSettings(difficulty: .standard)

    #expect(
        try evaluator.evaluate(beforeFold, settings: settings).positionBasisPoints
            == evaluator.evaluate(afterFold, settings: settings).positionBasisPoints
    )
}

@Test func 合法候选严格来自规则引擎动作集合() throws {
    let observation = try makeStrategyObservation()
    let candidates = try RuleBasedEvaluator().legalCandidates(for: observation)

    #expect(candidates.map(\.kind) == [.fold, .call, .raise])
    let raise = try #require(candidates.first { $0.kind == .raise })
    #expect(raise.minimumAmount == Chips(rawValue: 400))
    #expect(raise.maximumAmount == Chips(rawValue: 1_000))
}

@Test func 候选生成拒绝颠倒的下注范围() throws {
    let observation = try makeStrategyObservation(
        legalActions: #"{"canFold":true,"canCheck":false,"callAmount":100,"minimumBet":null,"minimumRaiseTo":900,"maximumRaiseTo":800,"canAllIn":true}"#
    )

    #expect(throws: BotError.invalidObservation) {
        try RuleBasedEvaluator().legalCandidates(for: observation)
    }
}

private func makeSettings(difficulty: BotDifficulty) -> BotSettings {
    try! BotSettings(
        difficulty: difficulty,
        model: .balanced,
        aggression: 50,
        bluffFrequency: 30,
        callingWidth: 50,
        betSizing: 50,
        thinkingSpeed: .standard,
        analyzesHistory: true
    )
}

private func makeStrategyObservation(
    ownCards: String = #"[{"rank":14,"suit":3},{"rank":13,"suit":3}]"#,
    communityCards: String = "[]",
    legalActions: String = #"{"canFold":true,"canCheck":false,"callAmount":100,"minimumBet":null,"minimumRaiseTo":400,"maximumRaiseTo":1000,"canAllIn":true}"#,
    seatTwoHasFolded: Bool = true
) throws -> BotObservation {
    let street = communityCards == "[]" ? 0 : 1
    let json = """
    {
        "viewer":0,
        "ownHoleCards":\(ownCards),
        "communityCards":\(communityCards),
        "publicSeats":[
            {"id":0,"stack":900,"committedThisStreet":100,"committedThisHand":100,"hasFolded":false,"isAllIn":false,"isSittingOut":false},
            {"id":1,"stack":800,"committedThisStreet":200,"committedThisHand":200,"hasFolded":false,"isAllIn":false,"isSittingOut":false},
            {"id":2,"stack":1200,"committedThisStreet":0,"committedThisHand":0,"hasFolded":\(seatTwoHasFolded),"isAllIn":false,"isSittingOut":false}
        ],
        "currentActor":0,
        "street":\(street),
        "currentBet":200,
        "legalActions":\(legalActions),
        "actions":[]
    }
    """
    let player = try JSONDecoder().decode(
        PlayerObservation.self,
        from: Data(json.utf8)
    )
    return try BotObservation(
        handID: "strategy-hand",
        stateVersion: 1,
        config: HandConfig(
            smallBlind: Chips(rawValue: 50)!,
            bigBlind: Chips(rawValue: 100)!,
            dealer: SeatID(rawValue: 1)!
        ),
        observation: player
    )
}
