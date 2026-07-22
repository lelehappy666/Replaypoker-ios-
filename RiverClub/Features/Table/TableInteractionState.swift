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

struct ChipFlightParticle: Equatable, Identifiable {
    let id: Int
    let delay: CGFloat
    let arcHeight: CGFloat
    let landingOffset: CGSize
    let rotation: Angle
    let chipCount: Int
}

struct ChipFlightParticlePresentation: Equatable, Identifiable {
    let particle: ChipFlightParticle
    let progress: CGFloat
    let landingScale: CGFloat

    var id: Int { particle.id }
}

struct ChipFlightTimeline: Equatable {
    let particles: [ChipFlightParticle]

    init(amount: Int, eventToken: Int) {
        let count: Int
        switch amount {
        case ..<500: count = 5
        case ..<5_000: count = 6
        default: count = 7
        }
        let direction: CGFloat = eventToken.isMultiple(of: 2) ? 1 : -1
        particles = (0..<count).map { index in
            let alternating: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            return ChipFlightParticle(
                id: index,
                delay: CGFloat(index) * 0.052,
                arcHeight: direction * alternating * (8 + CGFloat(index) * 2.3),
                landingOffset: CGSize(
                    width: CGFloat((index % 3) - 1) * 2.2,
                    height: CGFloat(index.isMultiple(of: 2) ? -1 : 1) * 1.4
                ),
                rotation: .degrees(Double((index - count / 2) * 9)),
                chipCount: 2 + (index % 3)
            )
        }
    }

    func presentation(
        globalProgress: CGFloat,
        reduceMotion: Bool
    ) -> [ChipFlightParticlePresentation] {
        particles.map { particle in
            let delay = reduceMotion ? particle.delay * 0.35 : particle.delay
            let available = max(1 - delay, 0.001)
            let linear = min(max((globalProgress - delay) / available, 0), 1)
            let remaining = 1 - linear
            let eased = 1 - remaining * remaining * remaining
            let landingProgress = min(max((linear - 0.84) / 0.16, 0), 1)
            let bounce = 4 * landingProgress * (1 - landingProgress)
            return ChipFlightParticlePresentation(
                particle: particle,
                progress: reduceMotion ? linear : eased,
                landingScale: reduceMotion ? 1 : 1 - bounce * 0.10
            )
        }
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

    var chipFlightGlobalProgress: CGFloat {
        chipFlightSeat == nil ? 0 : progress
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
        guard let timeline = chipFlightTimeline,
              timeline.particles.indices.contains(index)
        else { return 0 }
        return timeline.presentation(
            globalProgress: progress,
            reduceMotion: reduceMotion
        )[index].progress
    }

    func chipArrivalProgress(reduceMotion: Bool) -> CGFloat {
        guard let timeline = chipFlightTimeline else { return 1 }
        let presentations = timeline.presentation(
            globalProgress: progress,
            reduceMotion: reduceMotion
        )
        guard !presentations.isEmpty else { return 1 }
        let total = presentations.reduce(CGFloat.zero) { $0 + $1.progress }
        return min(max(total / CGFloat(presentations.count), 0), 1)
    }

    private var chipFlightTimeline: ChipFlightTimeline? {
        guard let amount = chipFlightAmount?.rawValue else { return nil }
        return ChipFlightTimeline(amount: amount, eventToken: activeToken)
    }

    func displayedStack(
        finalAmount: Int,
        seat: SeatID,
        reduceMotion: Bool
    ) -> Int {
        guard seat == chipFlightSeat,
              let event,
              let amount = chipFlightAmount?.rawValue
        else { return max(finalAmount, 0) }

        let remaining = remainingFlightAmount(amount, reduceMotion: reduceMotion)
        switch event.kind {
        case .postBlind:
            return max(finalAmount + remaining, 0)
        case .returnUncalledBet, .awardPot:
            return max(finalAmount - remaining, 0)
        default:
            return max(finalAmount, 0)
        }
    }

    func displayedCommitment(
        finalAmount: Int,
        seat: SeatID,
        reduceMotion: Bool
    ) -> Int {
        guard seat == chipFlightSeat,
              let event,
              let amount = chipFlightAmount?.rawValue
        else { return max(finalAmount, 0) }

        let remaining = remainingFlightAmount(amount, reduceMotion: reduceMotion)
        switch event.kind {
        case .postBlind:
            return max(finalAmount - remaining, 0)
        case .moveCommitmentToPot, .returnUncalledBet:
            return max(finalAmount + remaining, 0)
        default:
            return max(finalAmount, 0)
        }
    }

    func displayedPot(finalAmount: Int, reduceMotion: Bool) -> Int {
        guard let event,
              let amount = chipFlightAmount?.rawValue
        else { return max(finalAmount, 0) }

        let remaining = remainingFlightAmount(amount, reduceMotion: reduceMotion)
        switch event.kind {
        case .moveCommitmentToPot:
            return max(finalAmount - remaining, 0)
        case .awardPot:
            return max(finalAmount + remaining, 0)
        default:
            return max(finalAmount, 0)
        }
    }

    private func remainingFlightAmount(_ amount: Int, reduceMotion: Bool) -> Int {
        let remainingProgress = 1 - chipArrivalProgress(reduceMotion: reduceMotion)
        return Int((CGFloat(amount) * remainingProgress).rounded())
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
