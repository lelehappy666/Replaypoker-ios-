import PokerCoordinator
import SwiftUI

enum PokerTableLayout {
    static let seatSize = CGSize(width: 108, height: 96)
    static let seatContentSize = CGSize(width: 104, height: 92)
    static let betControlSize = CGSize(width: 330, height: 164)
    static let communityCardSize = CGSize(width: 46, height: 62)
    static let humanHoleCardSize = CGSize(width: 42, height: 57)
    static let botHoleCardSize = CGSize(width: 34, height: 46)

    static func positions(for canvas: CGSize) -> [CGPoint] {
        let topY = topBarRegion(for: canvas).maxY + seatSize.height / 2 + 2
        let bottomY = canvas.height - seatSize.height / 2 - 2
        let leftX = seatSize.width / 2 + 2
        let rightX = canvas.width - seatSize.width / 2 - 2
        let sideTopY = max(canvas.height * 0.52, topY + seatSize.height + 4)
        let sideBottomY = min(bottomY - 16, sideTopY + seatSize.height)

        return [
            .init(x: canvas.width * 0.20, y: topY),
            .init(x: canvas.width * 0.50, y: topY),
            .init(x: canvas.width * 0.70, y: topY),
            .init(x: rightX, y: topY + seatSize.height / 2 + 2),
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
        let size = CGSize(width: min(270, canvas.width * 0.36), height: 104)
        return CGRect(
            x: canvas.width * 0.5 - size.width / 2,
            y: canvas.height * 0.565 - size.height / 2,
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
    let reduceMotion: Bool
    let animation: TableAnimationPresentation

    private var initials: String {
        String(seat.displayName.prefix(2))
    }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: -6) {
                ForEach(Array(seat.cards.enumerated()), id: \.offset) { _, card in
                    TableCardView(cardState: card)
                        .frame(
                            width: holeCardSize.width,
                            height: holeCardSize.height
                        )
                        .accessibilityIdentifier(
                            seat.isHuman ? "table.localHoleCard" : "table.botHoleCard"
                        )
                }
            }
            .frame(height: holeCardSize.height)
            .scaleEffect(holeCardScale)

            HStack(spacing: 4) {
                Text(initials)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(seat.isHuman ? RCTheme.gold : RCTheme.primaryText)
                    .frame(width: 30, height: 30)
                    .background(
                        seat.isHuman ? RCTheme.gold.opacity(0.24) : RCTheme.surfaceRaised,
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                seat.isHuman ? RCTheme.gold.opacity(0.72) : RCTheme.primaryText.opacity(0.24),
                                lineWidth: 1
                            )
                    }

                VStack(alignment: .leading, spacing: 0) {
                    Text(seat.displayName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Text(seat.stack.rawValue.formatted())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(RCTheme.gold)
                }
            }

        }
        .overlay(alignment: .bottomTrailing) {
            if showsStatus {
                Text(statusText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(RCTheme.background)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RCTheme.gold, in: Capsule())
                    .offset(y: 3)
            }
        }
        .foregroundStyle(RCTheme.primaryText)
        .frame(
            width: PokerTableLayout.seatContentSize.width,
            height: PokerTableLayout.seatContentSize.height
        )
        .padding(2)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isWinner || seat.isCurrentActor ? RCTheme.gold : .clear, lineWidth: 2)
        }
        .scaleEffect(reduceMotion ? 1 : animation.winnerScale(for: seat.id))
        .opacity(seat.hasFolded ? 0.58 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    private var holeCardScale: CGFloat {
        reduceMotion ? 1 : animation.holeCardScale(for: seat.id)
    }

    private var holeCardSize: CGSize {
        seat.isHuman
            ? PokerTableLayout.humanHoleCardSize
            : PokerTableLayout.botHoleCardSize
    }

    private var showsStatus: Bool {
        seat.isCurrentActor || seat.hasFolded || seat.isAllIn
    }

    private var statusText: String {
        if seat.hasFolded { return "已弃牌" }
        if seat.isAllIn { return "全下" }
        if let secondsRemaining { return "行动中 · \(secondsRemaining)秒" }
        return "行动中"
    }

    private var accessibilityDescription: String {
        var result = "\(seat.isHuman ? "本人" : "玩家")\(seat.displayName)，娱乐筹码 \(seat.stack.rawValue)"
        if seat.isCurrentActor { result += "，\(statusText)" }
        if seat.hasFolded { result += "，已弃牌" }
        if seat.isAllIn { result += "，全下" }
        return result
    }
}
