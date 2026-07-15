import PokerCore

struct BotModelWeights: Equatable, Sendable {
    let fold: Int
    let call: Int
    let aggressive: Int
}

public struct BotDecisionEngine: Sendable {
    private let evaluator: RuleBasedEvaluator
    private let equityEstimator: any EquityEstimating

    public init() {
        evaluator = RuleBasedEvaluator()
        equityEstimator = MonteCarloEstimator()
    }

    init(equityEstimator: any EquityEstimating) {
        evaluator = RuleBasedEvaluator()
        self.equityEstimator = equityEstimator
    }

    public func decide(
        observation: BotObservation,
        settings: BotSettings,
        stableIdentity: String,
        seed: UInt64,
        history: BotHistorySummary? = nil
    ) async throws -> BotDecision {
        let evaluation = try evaluator.evaluate(observation, settings: settings)
        let candidates = try evaluator.legalCandidates(for: observation)
        let personality = BotPersonality.offsets(
            for: stableIdentity,
            schemaVersion: settings.schemaVersion
        )
        let effectiveHistory = settings.analyzesHistory ? history : nil
        let weights = Self.modelWeights(
            for: settings.model,
            history: effectiveHistory
        )

        let iterations: Int
        let strength: Int
        if settings.difficulty == .hard {
            iterations = settings.thinkingSpeed.hardSimulationIterations
            let estimate = try await equityEstimator.estimate(
                observation,
                iterations: iterations,
                seed: mixedSeed(seed, stableIdentity: stableIdentity)
            )
            strength = (evaluation.strengthBasisPoints + estimate.effectiveBasisPoints * 2) / 3
        } else {
            iterations = 0
            strength = evaluation.strengthBasisPoints
        }

        let aggression = personality.applying(to: settings.aggression, keyPath: \.aggression)
        let bluff = personality.applying(to: settings.bluffFrequency, keyPath: \.bluffFrequency)
        let calling = personality.applying(to: settings.callingWidth, keyPath: \.callingWidth)
        let sizing = personality.applying(to: settings.betSizing, keyPath: \.betSizing)
        let scored = candidates.map { candidate in
            (
                candidate,
                max(
                    1,
                    score(
                        candidate,
                        strength: strength,
                        aggression: aggression,
                        bluff: bluff,
                        calling: calling,
                        weights: weights
                    )
                )
            )
        }
        let candidate = choose(scored, seed: mixedSeed(seed, stableIdentity: stableIdentity))
        let action = try action(for: candidate, sizing: sizing)
        let reason: BotDecisionReason
        if settings.difficulty == .hard {
            reason = .simulatedEquity
        } else if settings.model == .adaptive,
                  effectiveHistory?.sampleCount ?? 0 >= 20 {
            reason = .adaptiveHistory
        } else {
            reason = .ruleEvaluation
        }

        return BotDecision(
            action: action,
            handID: observation.handID,
            stateVersion: observation.stateVersion,
            reason: reason,
            simulationIterations: iterations
        )
    }

    static func modelWeights(
        for model: BotModel,
        history: BotHistorySummary?
    ) -> BotModelWeights {
        switch model {
        case .conservative:
            return BotModelWeights(fold: 1_800, call: 500, aggressive: -1_500)
        case .balanced:
            return BotModelWeights(fold: 0, call: 0, aggressive: 0)
        case .aggressive:
            return BotModelWeights(fold: -1_200, call: -300, aggressive: 1_800)
        case .adaptive:
            guard let history, history.sampleCount >= 20 else {
                return BotModelWeights(fold: 0, call: 0, aggressive: 0)
            }
            return BotModelWeights(
                fold: max(0, history.opponentAggressionBasisPoints - 5_000) / 3,
                call: max(0, history.opponentAggressionBasisPoints - 5_000) / 4,
                aggressive: max(0, history.opponentFoldBasisPoints - 4_000) / 2
            )
        }
    }

    private func score(
        _ candidate: ActionCandidate,
        strength: Int,
        aggression: Int,
        bluff: Int,
        calling: Int,
        weights: BotModelWeights
    ) -> Int {
        let bluffPressure = (10_000 - strength) * bluff / 100
        switch candidate.kind {
        case .fold:
            return 8_000 - strength + weights.fold
        case .check:
            return 3_500 + strength / 2
        case .call:
            return strength + calling * 35 + weights.call
        case .bet, .raise:
            return strength + aggression * 40 + bluffPressure / 3 + weights.aggressive
        case .allIn:
            return strength * 3 / 2 + aggression * 25 + bluffPressure / 8
                + weights.aggressive
        }
    }

    private func choose(
        _ candidates: [(candidate: ActionCandidate, score: Int)],
        seed: UInt64
    ) -> ActionCandidate {
        let total = candidates.reduce(0) { $0 + $1.score }
        var generator = BotSeededGenerator(seed: seed)
        var selection = Int(generator.next() % UInt64(total))
        for entry in candidates {
            if selection < entry.score { return entry.candidate }
            selection -= entry.score
        }
        return candidates[candidates.count - 1].candidate
    }

    private func action(
        for candidate: ActionCandidate,
        sizing: Int
    ) throws -> PlayerAction {
        switch candidate.kind {
        case .fold: return .fold
        case .check: return .check
        case .call: return .call
        case .allIn: return .allIn
        case .bet, .raise:
            guard let minimum = candidate.minimumAmount,
                  let maximum = candidate.maximumAmount,
                  minimum <= maximum else {
                throw BotError.invalidObservation
            }
            let distance = maximum.rawValue - minimum.rawValue
            let amount = minimum.rawValue + distance * sizing / 100
            guard let chips = Chips(rawValue: amount) else {
                throw BotError.invalidObservation
            }
            return candidate.kind == .bet ? .bet(chips) : .raiseTo(chips)
        }
    }

    private func mixedSeed(_ seed: UInt64, stableIdentity: String) -> UInt64 {
        var result = seed ^ 14_695_981_039_346_656_037
        for byte in stableIdentity.utf8 {
            result ^= UInt64(byte)
            result &*= 1_099_511_628_211
        }
        return result
    }
}
