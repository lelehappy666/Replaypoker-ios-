import PokerCoordinator
import SwiftUI

enum PokerTableLayout {
    static let seatSize = CGSize(width: 104, height: 92)
    static let betControlSize = CGSize(width: 330, height: 164)

    static func positions(for canvas: CGSize) -> [CGPoint] {
        let topY = topBarRegion(for: canvas).maxY + seatSize.height / 2 + 2
        let bottomY = canvas.height - seatSize.height / 2 - 2
        let leftX = seatSize.width / 2 + 2
        let rightX = canvas.width - seatSize.width / 2 - 2
        let sideTopY = max(canvas.height * 0.52, topY + seatSize.height + 4)
        let sideBottomY = min(bottomY - 18, sideTopY + seatSize.height + 8)

        return [
            .init(x: canvas.width * 0.20, y: topY),
            .init(x: canvas.width * 0.50, y: topY),
            .init(x: canvas.width * 0.70, y: topY),
            .init(x: rightX, y: topY + seatSize.height / 2 + 4),
            .init(x: leftX, y: sideTopY),
            .init(x: leftX, y: sideBottomY),
            .init(x: canvas.width * 0.22, y: bottomY),
            .init(x: canvas.width * 0.36, y: bottomY),
            .init(x: canvas.width * 0.50, y: bottomY),
        ]
    }

    static func seatFrames(for canvas: CGSize) -> [CGRect] {
        positions(for: canvas).map {
            CGRect(
                x: $0.x - seatSize.width / 2,
                y: $0.y - seatSize.height / 2,
                width: seatSize.width,
                height: seatSize.height
            )
        }
    }

    static func safeCanvas(for canvas: CGSize) -> CGRect {
        CGRect(origin: .zero, size: canvas)
    }

    static func topBarRegion(for canvas: CGSize) -> CGRect {
        CGRect(x: 0, y: 0, width: canvas.width, height: 48)
    }

    static func centerBoardRegion(for canvas: CGSize) -> CGRect {
        let size = CGSize(width: min(250, canvas.width * 0.32), height: 90)
        return CGRect(
            x: canvas.width * 0.5 - size.width / 2,
            y: canvas.height * 0.54 - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func betControlRegion(for canvas: CGSize) -> CGRect {
        CGRect(
            x: canvas.width - betControlSize.width,
            y: canvas.height - betControlSize.height,
            width: betControlSize.width,
            height: betControlSize.height
        )
    }
}

struct PokerSeatView: View {
    let seat: TableSeatState
    let secondsRemaining: Int?
    let isWinner: Bool
    let animationPulse: Bool
    let reduceMotion: Bool
    let animation: TableAnimationEvent?

    private var isHuman: Bool {
        seat.cards.contains { card in
            if case .faceUp = card { return true }
            return false
        }
    }

    private var initials: String {
        String(seat.displayName.prefix(2))
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: -6) {
                ForEach(Array(seat.cards.enumerated()), id: \.offset) { _, card in
                    TableCardView(cardState: card)
                        .frame(width: 29, height: 39)
                        .accessibilityIdentifier(
                            isHuman ? "table.localHoleCard" : "table.botHoleCard"
                        )
                }
            }
            .frame(height: 39)
            .scaleEffect(holeCardScale)

            HStack(spacing: 4) {
                Text(initials)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isHuman ? RCTheme.gold : RCTheme.primaryText)
                    .frame(width: 26, height: 26)
                    .background(
                        isHuman ? RCTheme.gold.opacity(0.24) : RCTheme.surfaceRaised,
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 0) {
                    Text(seat.displayName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Text(seat.stack.rawValue.formatted())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(RCTheme.gold)
                }
            }

            if seat.isCurrentActor || seat.hasFolded || seat.isAllIn {
                Text(statusText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(RCTheme.background)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RCTheme.gold, in: Capsule())
            }
        }
        .foregroundStyle(RCTheme.primaryText)
        .frame(width: PokerTableLayout.seatSize.width, height: PokerTableLayout.seatSize.height)
        .padding(2)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isWinner || seat.isCurrentActor ? RCTheme.gold : .clear, lineWidth: 2)
        }
        .scaleEffect(isWinner && animationPulse && !reduceMotion ? 1.08 : 1)
        .opacity(seat.hasFolded ? 0.58 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    private var holeCardScale: CGFloat {
        guard !reduceMotion,
              case let .dealHoleCard(animatedSeat, _)? = animation,
              animatedSeat == seat.id
        else { return 1 }
        return animationPulse ? 1 : 0.72
    }

    private var statusText: String {
        if seat.hasFolded { return "已弃牌" }
        if seat.isAllIn { return "全下" }
        if let secondsRemaining { return "行动中 · \(secondsRemaining)秒" }
        return "行动中"
    }

    private var accessibilityDescription: String {
        var result = "\(isHuman ? "本人" : "玩家")\(seat.displayName)，娱乐筹码 \(seat.stack.rawValue)"
        if seat.isCurrentActor { result += "，\(statusText)" }
        if seat.hasFolded { result += "，已弃牌" }
        if seat.isAllIn { result += "，全下" }
        return result
    }
}
