import Foundation
import PokerCore

enum CashTableAnimationTiming {
    static func duration(
        for event: TableAnimationEvent,
        street: Street?,
        reduceMotion: Bool
    ) -> Duration {
        guard !reduceMotion else { return .zero }
        switch event {
        case .dealHoleCard:
            return .milliseconds(80)
        case .showAction, .moveCommitmentToPot:
            return .milliseconds(250)
        case .revealCommunityCard:
            return street == .flop ? .milliseconds(180) : .milliseconds(220)
        case .returnUncalledBet, .awardPot, .highlightWinner:
            return .milliseconds(650)
        case .postBlind, .streetChanged:
            return .zero
        }
    }
}
