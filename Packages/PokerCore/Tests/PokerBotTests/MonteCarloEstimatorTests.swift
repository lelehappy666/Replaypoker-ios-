import Foundation
import PokerCore
import Testing
@testable import PokerBot

@Test func 未知牌采样排除已知牌且自身不重复() throws {
    let known = try decodeCards(
        #"[{"rank":14,"suit":3},{"rank":13,"suit":3},{"rank":12,"suit":3}]"#
    )
    let sampler = try UnknownCardSampler(knownCards: known)
    var generator = BotSeededGenerator(seed: 42)
    let sample = try sampler.sample(count: 20, using: &generator)

    #expect(Set(sample).count == 20)
    #expect(Set(sample).isDisjoint(with: known))
}

@Test func 相同观察和种子产生相同权益() async throws {
    let observation = try makeSimulationObservation()
    let estimator = MonteCarloEstimator()

    let first = try await estimator.estimate(
        observation,
        iterations: 800,
        seed: 73
    )
    let second = try await estimator.estimate(
        observation,
        iterations: 800,
        seed: 73
    )

    #expect(first == second)
    #expect(first.iterations == 800)
}

@Test func 河牌皇家同花顺获得百分百胜率() async throws {
    let observation = try makeSimulationObservation(
        ownCards: #"[{"rank":14,"suit":3},{"rank":13,"suit":3}]"#,
        communityCards: #"[{"rank":12,"suit":3},{"rank":11,"suit":3},{"rank":10,"suit":3},{"rank":2,"suit":1},{"rank":3,"suit":0}]"#,
        street: 3
    )

    let result = try await MonteCarloEstimator().estimate(
        observation,
        iterations: 800,
        seed: 91
    )

    #expect(result.winBasisPoints == 10_000)
    #expect(result.tieBasisPoints == 0)
    #expect(result.effectiveBasisPoints == 10_000)
}

@Test func 长时间模拟响应任务取消() async throws {
    let observation = try makeSimulationObservation()
    let task = Task {
        try await MonteCarloEstimator().estimate(
            observation,
            iterations: 2_000_000,
            seed: 7
        )
    }
    task.cancel()

    await #expect(throws: CancellationError.self) {
        try await task.value
    }
}

@Test func 采样拒绝重复已知牌和过量请求() throws {
    let ace = try decodeCards(#"[{"rank":14,"suit":3}]"#)[0]
    #expect(throws: BotError.invalidObservation) {
        try UnknownCardSampler(knownCards: [ace, ace])
    }

    let sampler = try UnknownCardSampler(knownCards: [ace])
    var generator = BotSeededGenerator(seed: 1)
    #expect(throws: BotError.invalidObservation) {
        try sampler.sample(count: 52, using: &generator)
    }
}

@Test func 模拟拒绝重复公开座位() async throws {
    let observation = try makeSimulationObservation(seatTwoID: 1)

    await #expect(throws: BotError.invalidObservation) {
        try await MonteCarloEstimator().estimate(
            observation,
            iterations: 10,
            seed: 1
        )
    }
}

func makeSimulationObservation(
    ownCards: String = #"[{"rank":14,"suit":3},{"rank":13,"suit":2}]"#,
    communityCards: String = #"[{"rank":2,"suit":0},{"rank":7,"suit":1},{"rank":10,"suit":2}]"#,
    street: Int = 1,
    seatTwoID: Int = 2
) throws -> BotObservation {
    let json = """
    {
        "viewer":0,
        "ownHoleCards":\(ownCards),
        "communityCards":\(communityCards),
        "publicSeats":[
            {"id":0,"stack":900,"committedThisStreet":100,"committedThisHand":100,"hasFolded":false,"isAllIn":false,"isSittingOut":false},
            {"id":1,"stack":800,"committedThisStreet":200,"committedThisHand":200,"hasFolded":false,"isAllIn":false,"isSittingOut":false},
            {"id":\(seatTwoID),"stack":1200,"committedThisStreet":200,"committedThisHand":200,"hasFolded":false,"isAllIn":false,"isSittingOut":false}
        ],
        "currentActor":0,
        "street":\(street),
        "currentBet":200,
        "legalActions":{"canFold":true,"canCheck":false,"callAmount":100,"minimumBet":null,"minimumRaiseTo":400,"maximumRaiseTo":1000,"canAllIn":true},
        "actions":[]
    }
    """
    let player = try JSONDecoder().decode(
        PlayerObservation.self,
        from: Data(json.utf8)
    )
    return try BotObservation(
        handID: "simulation-hand",
        stateVersion: 1,
        config: HandConfig(
            smallBlind: Chips(rawValue: 50)!,
            bigBlind: Chips(rawValue: 100)!,
            dealer: SeatID(rawValue: 1)!
        ),
        observation: player
    )
}

private func decodeCards(_ json: String) throws -> [Card] {
    try JSONDecoder().decode([Card].self, from: Data(json.utf8))
}
