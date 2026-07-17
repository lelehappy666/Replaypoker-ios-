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
    static let betStackBaseSize = CGSize(width: 68, height: 44)
    static let potSize = CGSize(width: 110, height: 34)
    static let currentHandHeight: CGFloat = 14

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
        let topProgresses: [CGFloat] = [0, 0.16, 0.32, 0.68, 0.84, 1]
        let topPositions = topProgresses.map { progress in
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
        let size = CGSize(width: min(270, canvas.width - 2 * betControlSize.width - 8), height: 150)
        return CGRect(
            x: canvas.width * 0.5 - size.width / 2,
            y: canvas.height * 0.558_333_333_3 - size.height / 2,
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
        let y = board.minY + 42

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

    static func currentHandFrame(for canvas: CGSize) -> CGRect {
        let board = centerBoardRegion(for: canvas)
        let width = min(180, board.width - 16)
        return CGRect(
            x: board.midX - width / 2,
            y: board.minY + 6,
            width: width,
            height: currentHandHeight
        )
    }

    static func potFrame(for canvas: CGSize) -> CGRect {
        let board = centerBoardRegion(for: canvas)
        let slotBottom = communityCardFrames(for: canvas).map(\.maxY).max() ?? board.minY
        return CGRect(
            x: board.midX - potSize.width / 2,
            y: slotBottom + 4,
            width: potSize.width,
            height: potSize.height
        )
    }

    static func betPosition(forSeatAt index: Int, canvas: CGSize) -> CGPoint? {
        guard let frame = betFrame(forSeatAt: index, canvas: canvas) else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    static func betScale(for canvas: CGSize) -> CGFloat {
        seatFrameSize(for: canvas).width / seatSize.width
    }

    static func betFrame(forSeatAt index: Int, canvas: CGSize) -> CGRect? {
        let frames = betFrames(for: canvas)
        guard frames.indices.contains(index) else { return nil }
        return frames[index]
    }

    static func betFrames(for canvas: CGSize) -> [CGRect?] {
        let seats = seatFrames(for: canvas)
        guard seats.count == 9 else { return [] }

        var result = Array<CGRect?>(repeating: nil, count: seats.count)
        let candidates = seats.indices.map { betCandidates(forSeatAt: $0, canvas: canvas) }
        var visitedNodes = 0
        let maximumSearchNodes = 12_000
        let selectionOrder = seats.indices.sorted {
            candidates[$0].count == candidates[$1].count ? $0 < $1 : candidates[$0].count < candidates[$1].count
        }

        func search(_ orderIndex: Int, selected: [CGRect]) -> Bool {
            guard orderIndex < selectionOrder.count else { return true }
            let seatIndex = selectionOrder[orderIndex]

            for candidate in candidates[seatIndex] {
                guard selected.allSatisfy({ !$0.intersects(candidate) }) else { continue }
                visitedNodes += 1
                guard visitedNodes <= maximumSearchNodes else { return false }

                let nextSelected = selected + [candidate]
                let remainingSeatsHaveSpace = selectionOrder.dropFirst(orderIndex + 1).allSatisfy { remainingSeatIndex in
                    candidates[remainingSeatIndex].contains { futureCandidate in
                        nextSelected.allSatisfy { !$0.intersects(futureCandidate) }
                    }
                }
                guard remainingSeatsHaveSpace else { continue }

                result[seatIndex] = candidate
                if search(orderIndex + 1, selected: nextSelected) {
                    return true
                }
                result[seatIndex] = nil
            }
            return false
        }

        return search(0, selected: []) ? result : Array(repeating: nil, count: seats.count)
    }

    static func betCandidateCounts(for canvas: CGSize) -> [Int] {
        seatFrames(for: canvas).indices.map { betCandidates(forSeatAt: $0, canvas: canvas).count }
    }

    private static func betCandidates(forSeatAt index: Int, canvas: CGSize) -> [CGRect] {
        let seats = seatFrames(for: canvas)
        let scale = betScale(for: canvas)
        let size = CGSize(
            width: betStackBaseSize.width * scale,
            height: betStackBaseSize.height * scale
        )
        let center = tableCenter(for: canvas)
        guard seats.indices.contains(index) else { return [] }

        let seat = seats[index]
        let seatCenter = CGPoint(x: seat.midX, y: seat.midY)
        let horizontal = center.x - seatCenter.x
        let vertical = center.y - seatCenter.y
        let length = (horizontal * horizontal + vertical * vertical).squareRoot()
        guard length > 0 else { return [] }

        let perpendicular = CGPoint(x: -vertical / length, y: horizontal / length)
        let progresses: [CGFloat] = [0.32, 0.40, 0.48, 0.56, 0.64, 0.72]
        let offsets: [CGFloat] = [
            0,
            -betStackBaseSize.width * 0.55,
            betStackBaseSize.width * 0.55,
            -betStackBaseSize.width,
            betStackBaseSize.width,
            -betStackBaseSize.width * 1.45,
            betStackBaseSize.width * 1.45,
            -betStackBaseSize.width * 1.75,
            betStackBaseSize.width * 1.75,
        ]
        let slots = communityCardFrames(for: canvas)
        let action = betControlRegion(for: canvas)
        let safeCanvas = safeCanvas(for: canvas)
        let hand = currentHandFrame(for: canvas)
        let pot = potFrame(for: canvas)
        var result: [CGRect] = []

        for progress in progresses {
            for baseOffset in offsets {
                let offset = baseOffset * scale
                let point = CGPoint(
                    x: seatCenter.x + horizontal * progress + perpendicular.x * offset,
                    y: seatCenter.y + vertical * progress + perpendicular.y * offset
                )
                let centerDistanceX = point.x - center.x
                let centerDistanceY = point.y - center.y
                guard centerDistanceX * centerDistanceX + centerDistanceY * centerDistanceY < length * length else {
                    continue
                }

                let frame = CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                guard safeCanvas.contains(frame),
                      seats.allSatisfy({ !$0.intersects(frame) }),
                      slots.allSatisfy({ !$0.intersects(frame) }),
                      !action.intersects(frame),
                      !hand.intersects(frame),
                      !pot.intersects(frame) else {
                    continue
                }
                guard !result.contains(where: { $0.equalTo(frame) }) else { continue }
                result.append(frame)
            }
        }

        return result
    }

    static func vectorFromPot(
        toSeatAt index: Int,
        canvas: CGSize
    ) -> CGVector? {
        let positions = positions(for: canvas)
        guard positions.indices.contains(index) else { return nil }
        let potFrame = potFrame(for: canvas)
        let pot = CGPoint(x: potFrame.midX, y: potFrame.midY)
        return CGVector(
            dx: positions[index].x - pot.x,
            dy: positions[index].y - pot.y
        )
    }

    static func payoutPosition(
        toSeatAt index: Int,
        canvas: CGSize,
        progress: CGFloat
    ) -> CGPoint? {
        let positions = positions(for: canvas)
        guard positions.indices.contains(index) else { return nil }
        let potFrame = potFrame(for: canvas)
        let start = CGPoint(x: potFrame.midX, y: potFrame.midY)
        let clampedProgress = min(max(progress, 0), 1)
        let target = positions[index]
        return CGPoint(
            x: start.x + (target.x - start.x) * clampedProgress,
            y: start.y + (target.y - start.y) * clampedProgress
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
                    .accessibilityValue(seat.displayName)

                VStack(alignment: .leading, spacing: 0) {
                    Text(seat.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(seat.stack.rawValue.formatted())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(RCTheme.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if showsStatus {
                        Text(statusText)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(RCTheme.gold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .accessibilityIdentifier("table.seatStatus.\(seat.id.rawValue)")
                    }
                }
            }
            .frame(height: 30)

        }
        .foregroundStyle(RCTheme.primaryText)
        .frame(
            width: PokerTableLayout.seatSize.width,
            height: PokerTableLayout.seatSize.height
        )
        .background(.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isWinner || seat.isCurrentActor ? RCTheme.gold : .clear, lineWidth: 2)
        }
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
