import Foundation
import PokerCore

enum CashTableAnimationTiming {
    static func duration(
        for event: TableAnimationEvent,
        street: Street?,
        reduceMotion: Bool
    ) -> Duration {
        if reduceMotion {
            switch event {
            case .postBlind, .moveCommitmentToPot:
                return .milliseconds(360)
            case .returnUncalledBet:
                return .milliseconds(460)
            case .awardPot:
                return .milliseconds(600)
            default:
                return .zero
            }
        }
        switch event {
        case .dealHoleCard:
            return .milliseconds(80)
        case .showAction:
            return .milliseconds(250)
        case .postBlind, .moveCommitmentToPot:
            return .milliseconds(620)
        case .revealCommunityCard:
            return street == .flop ? .milliseconds(180) : .milliseconds(220)
        case .returnUncalledBet:
            return .milliseconds(620)
        case .awardPot:
            return .milliseconds(780)
        case .highlightWinner:
            return .milliseconds(650)
        case .streetChanged:
            return .zero
        }
    }
}
