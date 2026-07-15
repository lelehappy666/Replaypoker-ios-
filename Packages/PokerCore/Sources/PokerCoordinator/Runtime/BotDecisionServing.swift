import PokerBot

package protocol BotDecisionServing: Sendable {
    func decide(_ request: BotDecisionRequest) async -> BotDecision?
    func cancel(handID: String) async
}

extension BotDecisionService: BotDecisionServing {}
