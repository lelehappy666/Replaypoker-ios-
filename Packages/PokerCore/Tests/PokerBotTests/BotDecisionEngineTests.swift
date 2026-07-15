import PokerCore
import Testing
@testable import PokerBot

@Test func 三档难度只在困难档调用规定次数的模拟() async throws {
    let observation = try makeSimulationObservation()

    for (difficulty, speed, expected) in [
        (BotDifficulty.easy, BotThinkingSpeed.natural, 0),
        (.standard, .natural, 0),
        (.hard, .fast, 800),
        (.hard, .standard, 2_000),
        (.hard, .natural, 5_000),
    ] {
        let estimator = CountingEquityEstimator(equity: 6_500)
        let engine = BotDecisionEngine(equityEstimator: estimator)
        let decision = try await engine.decide(
            observation: observation,
            settings: try decisionSettings(difficulty: difficulty, thinkingSpeed: speed),
            stableIdentity: "机器人-1",
            seed: 42
        )

        #expect(decision.simulationIterations == expected)
        #expect(await estimator.iterations() == (expected == 0 ? [] : [expected]))
        #expect(isLegal(decision.action, in: observation.legalActions))
    }
}

@Test func 四种模型权重方向符合设置语义() {
    let conservative = BotDecisionEngine.modelWeights(for: .conservative, history: nil)
    let balanced = BotDecisionEngine.modelWeights(for: .balanced, history: nil)
    let aggressive = BotDecisionEngine.modelWeights(for: .aggressive, history: nil)
    let adaptive = BotDecisionEngine.modelWeights(for: .adaptive, history: nil)

    #expect(conservative.fold > balanced.fold)
    #expect(conservative.aggressive < balanced.aggressive)
    #expect(aggressive.fold < balanced.fold)
    #expect(aggressive.aggressive > balanced.aggressive)
    #expect(adaptive == balanced)
}

@Test func 相同输入身份与种子产生完全相同决定() async throws {
    let observation = try makeSimulationObservation()
    let settings = try decisionSettings(difficulty: .standard)
    let engine = BotDecisionEngine()

    let first = try await engine.decide(
        observation: observation,
        settings: settings,
        stableIdentity: "稳定身份",
        seed: 99
    )
    let second = try await engine.decide(
        observation: observation,
        settings: settings,
        stableIdentity: "稳定身份",
        seed: 99
    )

    #expect(first == second)
    #expect(first.handID == observation.handID)
    #expect(first.stateVersion == observation.stateVersion)
}

@Test func 历史关闭时忽略摘要且自适应无样本退化为均衡型() async throws {
    let observation = try makeSimulationObservation()
    let summary = BotHistorySummary(
        sampleCount: 100,
        opponentFoldBasisPoints: 9_000,
        opponentAggressionBasisPoints: 9_000
    )
    let off = try decisionSettings(model: .adaptive, analyzesHistory: false)
    let engine = BotDecisionEngine()

    let ignored = try await engine.decide(
        observation: observation, settings: off, stableIdentity: "A", seed: 7,
        history: summary
    )
    let absent = try await engine.decide(
        observation: observation, settings: off, stableIdentity: "A", seed: 7,
        history: nil
    )
    #expect(ignored == absent)

    let noSamples = BotDecisionEngine.modelWeights(
        for: .adaptive,
        history: BotHistorySummary(sampleCount: 0, opponentFoldBasisPoints: 10_000, opponentAggressionBasisPoints: 10_000)
    )
    #expect(noSamples == BotDecisionEngine.modelWeights(for: .balanced, history: nil))
}

actor CountingEquityEstimator: EquityEstimating {
    private let equity: Int
    private var calls: [Int] = []

    init(equity: Int) { self.equity = equity }

    func estimate(
        _ observation: BotObservation,
        iterations: Int,
        seed: UInt64
    ) async throws -> EquityEstimate {
        calls.append(iterations)
        return EquityEstimate(
            winBasisPoints: equity,
            tieBasisPoints: 0,
            effectiveBasisPoints: equity,
            iterations: iterations
        )
    }

    func iterations() -> [Int] { calls }
}

func decisionSettings(
    difficulty: BotDifficulty = .standard,
    model: BotModel = .balanced,
    aggression: Int = 50,
    bluffFrequency: Int = 30,
    callingWidth: Int = 50,
    betSizing: Int = 50,
    thinkingSpeed: BotThinkingSpeed = .standard,
    analyzesHistory: Bool = true
) throws -> BotSettings {
    try BotSettings(
        difficulty: difficulty,
        model: model,
        aggression: aggression,
        bluffFrequency: bluffFrequency,
        callingWidth: callingWidth,
        betSizing: betSizing,
        thinkingSpeed: thinkingSpeed,
        analyzesHistory: analyzesHistory
    )
}

func isLegal(_ action: PlayerAction, in legal: LegalActionSet) -> Bool {
    switch action {
    case .fold: legal.canFold
    case .check: legal.canCheck
    case .call: legal.callAmount != nil
    case let .bet(amount):
        legal.minimumBet.map { amount >= $0 } == true
            && legal.maximumRaiseTo.map { amount <= $0 } == true
    case let .raiseTo(amount):
        legal.minimumRaiseTo.map { amount >= $0 } == true
            && legal.maximumRaiseTo.map { amount <= $0 } == true
    case .allIn: legal.canAllIn
    }
}
