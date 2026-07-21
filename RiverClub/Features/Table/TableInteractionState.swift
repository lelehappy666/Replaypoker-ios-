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
        } catch is CancellationError {
            failedIntent = nil
            errorMessage = nil
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
            return failedIntent == .nextHand ? .nextHand : nil
        default:
            return nil
        }
    }

    func canRetry(for phase: TableFlowPhase) -> Bool {
        if phase == .suspended { return failedIntent != nil }
        return retryIntent(for: phase) != nil
    }

    func retry(
        for phase: TableFlowPhase,
        send: (TableIntent) async throws -> Void,
        resume: () async throws -> Void
    ) async {
        guard !isSending else { return }
        let intent = retryIntent(for: phase)
        guard phase == .suspended ? failedIntent != nil : intent != nil else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            if phase == .suspended {
                try await resume()
            } else if let intent {
                try await send(intent)
            }
            failedIntent = nil
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = phase == .suspended
                ? "恢复牌局失败，请重试。"
                : "操作失败，请重试。"
        }
    }

    func dismissError() {
        errorMessage = nil
        failedIntent = nil
    }
}

struct TableAnimationPresentation: Equatable {
    private(set) var event: TableAnimationEvent?
    private(set) var activeToken = 0
    private var progress: CGFloat = 0

    mutating func begin(_ event: TableAnimationEvent, token: Int) {
        self.event = event
        activeToken = token
        progress = 0
    }

    mutating func advance(token: Int, progress newProgress: CGFloat = 1) {
        guard activeToken == token, event != nil else { return }
        progress = min(max(newProgress, 0), 1)
    }

    mutating func reset(token: Int) {
        guard activeToken == token else { return }
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

    var awardTargetSeat: SeatID? {
        guard case let .awardPot(seat, _)? = event else { return nil }
        return seat
    }

    var awardAmount: Chips? {
        guard case let .awardPot(_, amount)? = event else { return nil }
        return amount
    }

    var awardProgress: CGFloat {
        awardTargetSeat == nil ? 0 : progress
    }

    var chipOffset: CGFloat {
        switch event?.kind {
        case .moveCommitmentToPot: 7 * progress
        case .returnUncalledBet: -7 * progress
        default: 0
        }
    }

    var chipFlightSeat: SeatID? {
        switch event {
        case let .postBlind(seat, _),
             let .moveCommitmentToPot(seat, _),
             let .returnUncalledBet(seat, _),
             let .awardPot(seat, _):
            seat
        default:
            nil
        }
    }

    var chipFlightAmount: Chips? {
        switch event {
        case let .postBlind(_, amount),
             let .moveCommitmentToPot(_, amount),
             let .returnUncalledBet(_, amount),
             let .awardPot(_, amount):
            amount
        default:
            nil
        }
    }

    func chipFlightProgress(at index: Int, reduceMotion: Bool) -> CGFloat {
        guard chipFlightSeat != nil, index >= 0, index < 4 else { return 0 }
        let delayStep: CGFloat = reduceMotion ? 0.04 : 0.08
        let delay = CGFloat(index) * delayStep
        let availableProgress = max(1 - delay, 0.001)
        return min(max((progress - delay) / availableProgress, 0), 1)
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
