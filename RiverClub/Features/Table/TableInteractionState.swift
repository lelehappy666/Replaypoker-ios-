import Observation
import PokerCoordinator
import PokerCore
import SwiftUI

@MainActor @Observable
final class TableActionRequestModel {
    private(set) var isSending = false
    private(set) var errorMessage: String?
    private var failedIntent: TableIntent?

    func send(
        _ intent: TableIntent,
        operation: (TableIntent) async throws -> Void
    ) async {
        guard !isSending else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            try await operation(intent)
            failedIntent = nil
        } catch {
            failedIntent = intent
            errorMessage = "操作失败，请重试。"
        }
    }

    func retryIntent(for phase: TableFlowPhase) -> TableIntent? {
        switch phase {
        case .waitingForHuman:
            guard let failedIntent else { return nil }
            switch failedIntent {
            case .fold, .middle, .aggressive:
                return failedIntent
            default:
                return nil
            }
        case .saveFailed:
            return .retrySave
        case .awaitingNextHand:
            return .nextHand
        default:
            return nil
        }
    }

    func dismissError() {
        errorMessage = nil
        failedIntent = nil
    }
}

struct TableAnimationPresentation: Equatable {
    private(set) var event: TableAnimationEvent?
    private var token = 0
    private var progress: CGFloat = 0

    mutating func begin(_ event: TableAnimationEvent, token: Int) {
        self.event = event
        self.token = token
        progress = 0
    }

    mutating func advance(token: Int) {
        guard self.token == token, event != nil else { return }
        progress = 1
    }

    mutating func reset(token: Int) {
        guard self.token == token else { return }
        event = nil
        progress = 0
    }

    func holeCardScale(for seat: SeatID) -> CGFloat {
        guard case let .dealHoleCard(animatedSeat, _)? = event,
              animatedSeat == seat
        else { return 1 }
        return 0.72 + 0.28 * progress
    }

    func communityCardScale(at index: Int) -> CGFloat {
        guard case let .revealCommunityCard(_, animatedIndex)? = event,
              animatedIndex == index
        else { return 1 }
        return 0.88 + 0.12 * progress
    }

    func communityCardOpacity(at index: Int) -> Double {
        guard case let .revealCommunityCard(_, animatedIndex)? = event,
              animatedIndex == index
        else { return 1 }
        return Double(progress)
    }

    var chipOffset: CGFloat {
        switch event?.kind {
        case .moveCommitmentToPot: 7 * progress
        case .returnUncalledBet: -7 * progress
        case .awardPot: -12 * progress
        default: 0
        }
    }

    func winnerScale(for seat: SeatID) -> CGFloat {
        isWinnerEvent(seat) ? 1 + 0.08 * progress : 1
    }

    func isWinnerHighlighted(_ seat: SeatID) -> Bool {
        isWinnerEvent(seat) && progress > 0
    }

    private func isWinnerEvent(_ seat: SeatID) -> Bool {
        guard case let .highlightWinner(winner)? = event else { return false }
        return winner == seat
    }
}
