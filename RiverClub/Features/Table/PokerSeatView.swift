import PokerCoordinator
import SwiftUI

enum PokerTableLayout {
    static let seatSize = CGSize(width: 108, height: 96)
    static let seatContentSize = CGSize(width: 104, height: 94)
    static let betControlSize = CGSize(width: 260, height: 128)
    static let cardAspectRatio: CGFloat = 34.0 / 46.0
    static let holeCardSpacing: CGFloat = 4
    static let communityCardSize = CGSize(width: 46, height: 62)
    static let humanHoleCardSize = CGSize(width: 46, height: 62)
    static let botHoleCardSize = CGSize(width: 38, height: 52)

    static func seatFrameSize(for canvas: CGSize) -> CGSize {
        let canvasScale = min(canvas.width / 956, canvas.height / 440)
        let compactScale = min(1, max(0.72, 1 - (1 - canvasScale) * 1.4))
        return CGSize(
            width: seatSize.width * compactScale,
            height: seatSize.height * compactScale
        )
    }

    static func positions(for canvas: CGSize) -> [CGPoint] {
        let frameSize = seatFrameSize(for: canvas)
        let topY = topBarRegion(for: canvas).maxY + frameSize.height / 2 + 4
        let bottomY = canvas.height - frameSize.height / 2 - 2
        let leftX = frameSize.width / 2
        let rightX = canvas.width - frameSize.width / 2
        let sideY = min(canvas.height * 0.59, bottomY - frameSize.height - 8)
        let topPositions = (0..<6).map { index in
            let progress = CGFloat(index) / 5
            return CGPoint(x: leftX + (rightX - leftX) * progress, y: topY)
        }

        // 0...7 沿可用外缘从左下顺时针排开，8 始终是本人底部中央。
        return [
            .init(x: canvas.width * 0.25, y: bottomY),
            .init(x: leftX, y: sideY),
        ] + topPositions + [
            .init(x: canvas.width * 0.50, y: bottomY),
        ]
    }

    static func seatFrames(for canvas: CGSize) -> [CGRect] {
        let frameSize = seatFrameSize(for: canvas)
        return positions(for: canvas).map {
            CGRect(
                x: $0.x - frameSize.width / 2,
                y: $0.y - frameSize.height / 2,
                width: frameSize.width,
                height: frameSize.height
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
        let size = CGSize(width: min(270, canvas.width - 2 * betControlSize.width - 8), height: 142)
        return CGRect(
            x: canvas.width * 0.5 - size.width / 2,
            y: canvas.height * 0.55 - size.height / 2,
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

    static func communityCardFrames(for canvas: CGSize) -> [CGRect] {
        let board = centerBoardRegion(for: canvas)
        let totalWidth = communityCardSize.width * 5 + holeCardSpacing * 4
        let startX = board.midX - totalWidth / 2
        let y = board.minY + 14

        return (0..<5).map { index in
            CGRect(
                x: startX + CGFloat(index) * (communityCardSize.width + holeCardSpacing),
                y: y,
                width: communityCardSize.width,
                height: communityCardSize.height
            )
        }
    }

    static func tableCenter(for canvas: CGSize) -> CGPoint {
        let board = centerBoardRegion(for: canvas)
        return CGPoint(x: board.midX, y: board.midY)
    }

    static func betPosition(forSeatAt index: Int, canvas: CGSize) -> CGPoint {
        let seatFrames = seatFrames(for: canvas)
        guard seatFrames.indices.contains(index) else { return tableCenter(for: canvas) }

        let seat = seatFrames[index]
        let seatCenter = CGPoint(x: seat.midX, y: seat.midY)
        let center = tableCenter(for: canvas)
        return CGPoint(
            x: seatCenter.x + (center.x - seatCenter.x) * 0.4,
            y: seatCenter.y + (center.y - seatCenter.y) * 0.4
        )
    }

    static func vectorFromPot(
        toSeatAt index: Int,
        canvas: CGSize
    ) -> CGVector? {
        let positions = positions(for: canvas)
        guard positions.indices.contains(index) else { return nil }
        let pot = tableCenter(for: canvas)
        return CGVector(
            dx: positions[index].x - pot.x,
            dy: positions[index].y - pot.y
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
            HStack(spacing: PokerTableLayout.holeCardSpacing) {
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
            .opacity(seat.hasFolded ? 0.44 : 1)

            HStack(spacing: 4) {
                RobotAvatarView(
                    imageName: seat.avatarAssetName,
                    fallbackText: initials,
                    size: 30
                )
                    .opacity(seat.hasFolded ? 0.44 : 1)
                    .accessibilityIdentifier(
                        seat.isHuman
                            ? "table.localAvatar"
                            : "table.botAvatar.\(seat.id.rawValue)"
                    )

                VStack(alignment: .leading, spacing: 0) {
                    Text(seat.displayName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Text(seat.stack.rawValue.formatted())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(RCTheme.gold)
                    if showsStatus {
                        Text(statusText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(RCTheme.gold)
                            .lineLimit(1)
                            .accessibilityIdentifier("table.seatStatus.\(seat.id.rawValue)")
                    }
                }
            }

        }
        .foregroundStyle(RCTheme.primaryText)
        .frame(
            width: PokerTableLayout.seatContentSize.width,
            height: PokerTableLayout.seatContentSize.height
        )
        .background(.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isWinner || seat.isCurrentActor ? RCTheme.gold : .clear, lineWidth: 2)
        }
        .scaleEffect(reduceMotion ? 1 : animation.winnerScale(for: seat.id))
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
