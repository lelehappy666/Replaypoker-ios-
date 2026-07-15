import PokerCore

enum CashTableActionPipeline {
    static func action(
        for intent: TableIntent,
        legalActions legal: LegalActionSet
    ) throws -> PlayerAction {
        switch intent {
        case .fold where legal.canFold:
            return .fold
        case .middle where legal.canCheck:
            return .check
        case .middle where legal.callAmount != nil:
            return .call
        case let .aggressive(amount)
            where amount == legal.maximumRaiseTo && legal.canAllIn:
            return .allIn
        case let .aggressive(amount)
            where legal.minimumBet.map({ amount >= $0 }) == true
                && legal.maximumRaiseTo.map({ amount <= $0 }) == true:
            return .bet(amount)
        case let .aggressive(amount)
            where legal.minimumRaiseTo.map({ amount >= $0 }) == true
                && legal.maximumRaiseTo.map({ amount <= $0 }) == true:
            return .raiseTo(amount)
        default:
            throw PokerCoordinatorError.illegalIntent
        }
    }
}
