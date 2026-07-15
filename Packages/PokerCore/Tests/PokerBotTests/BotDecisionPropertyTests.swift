import PokerCore
import Testing
@testable import PokerBot

@Test func 高级参数零推荐值和一百都只能产生合法动作() async throws {
    let observation = try makeSimulationObservation()
    let engine = BotDecisionEngine()

    for value in [0, 50, 100] {
        let settings = try decisionSettings(
            aggression: value,
            bluffFrequency: value,
            callingWidth: value,
            betSizing: value
        )
        for seed in 0..<100 {
            let decision = try await engine.decide(
                observation: observation,
                settings: settings,
                stableIdentity: "边界机器人",
                seed: UInt64(seed)
            )
            #expect(isLegal(decision.action, in: observation.legalActions))
        }
    }
}

@Test func 一千组确定性随机决策始终合法() async throws {
    let engine = BotDecisionEngine()
    let legalActionVariants = [
        #"{"canFold":true,"canCheck":false,"callAmount":100,"minimumBet":null,"minimumRaiseTo":400,"maximumRaiseTo":1000,"canAllIn":true}"#,
        #"{"canFold":false,"canCheck":true,"callAmount":null,"minimumBet":100,"minimumRaiseTo":null,"maximumRaiseTo":900,"canAllIn":true}"#,
        #"{"canFold":true,"canCheck":false,"callAmount":100,"minimumBet":null,"minimumRaiseTo":null,"maximumRaiseTo":900,"canAllIn":true}"#,
        #"{"canFold":false,"canCheck":true,"callAmount":null,"minimumBet":null,"minimumRaiseTo":null,"maximumRaiseTo":null,"canAllIn":false}"#,
    ]

    for seed in 0..<1_000 {
        let observation = try makeSimulationObservation(
            legalActions: legalActionVariants[seed % legalActionVariants.count],
            stateVersion: seed
        )
        let value = seed % 101
        let settings = try decisionSettings(
            model: BotModel.allCases[seed % BotModel.allCases.count],
            aggression: value,
            bluffFrequency: (value * 3) % 101,
            callingWidth: (value * 7) % 101,
            betSizing: (value * 11) % 101,
            analyzesHistory: seed.isMultiple(of: 2)
        )
        let decision = try await engine.decide(
            observation: observation,
            settings: settings,
            stableIdentity: "属性-\(seed % 9)",
            seed: UInt64(seed)
        )
        #expect(isLegal(decision.action, in: observation.legalActions))
    }
}
