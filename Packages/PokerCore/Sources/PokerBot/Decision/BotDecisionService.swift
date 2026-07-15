import PokerCore

public struct BotDecisionRequest: Equatable, Sendable {
    public let observation: BotObservation
    public let settings: BotSettings
    public let stableIdentity: String
    public let seed: UInt64
    public let history: BotHistorySummary?

    public init(
        observation: BotObservation,
        settings: BotSettings,
        stableIdentity: String,
        seed: UInt64,
        history: BotHistorySummary? = nil
    ) {
        self.observation = observation
        self.settings = settings
        self.stableIdentity = stableIdentity
        self.seed = seed
        self.history = history
    }
}

protocol BotDecisionMaking: Sendable {
    func decide(_ request: BotDecisionRequest) async throws -> BotDecision
}

extension BotDecisionEngine: BotDecisionMaking {
    func decide(_ request: BotDecisionRequest) async throws -> BotDecision {
        try await decide(
            observation: request.observation,
            settings: request.settings,
            stableIdentity: request.stableIdentity,
            seed: request.seed,
            history: request.history
        )
    }
}

enum FallbackAction {
    static func choose(from legal: LegalActionSet) throws -> PlayerAction {
        if legal.canCheck { return .check }
        if legal.canFold { return .fold }
        throw BotError.invalidObservation
    }
}

public actor BotDecisionService {
    private struct ActiveDecision: Sendable {
        let version: Int
        let token: UInt64
        let task: Task<WorkOutcome, Never>
    }

    private enum WorkOutcome: Sendable {
        case decision(BotDecision)
        case timedOut
        case failed
        case cancelled

        var isCancelled: Bool {
            if case .cancelled = self { return true }
            return false
        }
    }

    private let decisionMaker: any BotDecisionMaking
    private let timeout: Duration
    private let appliesDisplayDelay: Bool
    private var activeByHand: [String: ActiveDecision] = [:]
    private var highestVersionByHand: [String: Int] = [:]
    private var nextToken: UInt64 = 0

    public init(timeout: Duration = .seconds(15)) {
        decisionMaker = BotDecisionEngine()
        self.timeout = timeout
        appliesDisplayDelay = true
    }

    init(
        decisionMaker: any BotDecisionMaking,
        timeout: Duration,
        appliesDisplayDelay: Bool
    ) {
        self.decisionMaker = decisionMaker
        self.timeout = timeout
        self.appliesDisplayDelay = appliesDisplayDelay
    }

    public func decide(_ request: BotDecisionRequest) async -> BotDecision? {
        let handID = request.observation.handID
        let version = request.observation.stateVersion
        if let highest = highestVersionByHand[handID], version < highest {
            return nil
        }
        highestVersionByHand[handID] = version
        activeByHand[handID]?.task.cancel()
        nextToken &+= 1
        let token = nextToken
        let decisionMaker = self.decisionMaker
        let timeout = self.timeout
        let appliesDisplayDelay = self.appliesDisplayDelay
        let task = Task {
            await Self.perform(
                request,
                decisionMaker: decisionMaker,
                timeout: timeout,
                appliesDisplayDelay: appliesDisplayDelay
            )
        }
        activeByHand[handID] = ActiveDecision(
            version: version,
            token: token,
            task: task
        )

        let outcome = await task.value
        guard let active = activeByHand[handID],
              active.token == token,
              active.version == version else {
            return nil
        }
        activeByHand.removeValue(forKey: handID)

        switch outcome {
        case let .decision(decision):
            guard decision.handID == handID,
                  decision.stateVersion == version else {
                return fallback(for: request, reason: .fallbackError)
            }
            return decision
        case .timedOut:
            return fallback(for: request, reason: .fallbackTimeout)
        case .failed:
            return fallback(for: request, reason: .fallbackError)
        case .cancelled:
            return nil
        }
    }

    public func cancel(handID: String) {
        activeByHand.removeValue(forKey: handID)?.task.cancel()
    }

    static func displayDelayMilliseconds(
        speed: BotThinkingSpeed,
        seed: UInt64
    ) -> Int {
        let range: ClosedRange<Int>
        switch speed {
        case .fast: range = 200...500
        case .standard: range = 600...1_200
        case .natural: range = 1_200...2_500
        }
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        var generator = BotSeededGenerator(seed: seed ^ 0xD1B5_4A32_D192_ED03)
        return range.lowerBound + Int(generator.next() % width)
    }

    private static func perform(
        _ request: BotDecisionRequest,
        decisionMaker: any BotDecisionMaking,
        timeout: Duration,
        appliesDisplayDelay: Bool
    ) async -> WorkOutcome {
        let displayTask = Task {
            guard appliesDisplayDelay else { return }
            let milliseconds = displayDelayMilliseconds(
                speed: request.settings.thinkingSpeed,
                seed: request.seed
            )
            try await Task.sleep(for: .milliseconds(milliseconds))
        }
        let outcome = await raceDecision(
            request,
            decisionMaker: decisionMaker,
            timeout: timeout
        )
        if Task.isCancelled || outcome.isCancelled {
            displayTask.cancel()
            return .cancelled
        }
        do {
            try await displayTask.value
        } catch {
            return .cancelled
        }
        return outcome
    }

    private static func raceDecision(
        _ request: BotDecisionRequest,
        decisionMaker: any BotDecisionMaking,
        timeout: Duration
    ) async -> WorkOutcome {
        await withTaskGroup(of: WorkOutcome.self) { group in
            group.addTask {
                do {
                    return .decision(try await decisionMaker.decide(request))
                } catch is CancellationError {
                    return .cancelled
                } catch {
                    return .failed
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .timedOut
                } catch {
                    return .cancelled
                }
            }

            while let result = await group.next() {
                if case .cancelled = result, !Task.isCancelled {
                    continue
                }
                group.cancelAll()
                return result
            }
            return .cancelled
        }
    }

    private func fallback(
        for request: BotDecisionRequest,
        reason: BotDecisionReason
    ) -> BotDecision? {
        guard let action = try? FallbackAction.choose(
            from: request.observation.legalActions
        ) else {
            return nil
        }
        return BotDecision(
            action: action,
            handID: request.observation.handID,
            stateVersion: request.observation.stateVersion,
            reason: reason,
            simulationIterations: 0
        )
    }
}
