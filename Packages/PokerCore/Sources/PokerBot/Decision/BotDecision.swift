import PokerCore

public enum BotDecisionReason: String, Codable, Equatable, Sendable {
    case ruleEvaluation
    case simulatedEquity
    case adaptiveHistory
    case fallbackTimeout
    case fallbackError
}

public struct BotDecision: Codable, Equatable, Sendable {
    public let action: PlayerAction
    public let handID: String
    public let stateVersion: Int
    public let reason: BotDecisionReason
    public let simulationIterations: Int

    public init(
        action: PlayerAction,
        handID: String,
        stateVersion: Int,
        reason: BotDecisionReason,
        simulationIterations: Int
    ) {
        self.action = action
        self.handID = handID
        self.stateVersion = stateVersion
        self.reason = reason
        self.simulationIterations = simulationIterations
    }
}
