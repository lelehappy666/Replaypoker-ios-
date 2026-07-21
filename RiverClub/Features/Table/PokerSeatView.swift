import PokerCoordinator
import SwiftUI

enum PokerTableLayout {
    /// 以确认效果图 1844 × 853 的一半作为唯一布局坐标系。
    /// 实际设备只允许整体等比缩放，禁止座位、牌桌和操作区分别自适应。
    static let referenceCanvas = CGSize(width: 922, height: 426.5)
    static let seatSize = CGSize(width: 126, height: 116)
    static let seatContentSize = CGSize(width: 122, height: 112)
    static let betControlSize = CGSize(width: 265, height: 112)
    static let cardAspectRatio: CGFloat = 34.0 / 46.0
    static let holeCardSpacing: CGFloat = 7
    static let communityCardSize = CGSize(width: 50, height: 56)
    static let humanHoleCardSize = CGSize(width: 38, height: 50)
    static let botHoleCardSize = CGSize(width: 28, height: 38)
    static let betStackBaseSize = CGSize(width: 68, height: 44)
    static let potSize = CGSize(width: 142, height: 64)
    static let currentHandHeight: CGFloat = 14

    static func seatFrameSize(for canvas: CGSize) -> CGSize {
        let compactScale = referenceScale(for: canvas)
        return CGSize(
            width: seatSize.width * compactScale,
            height: seatSize.height * compactScale
        )
    }

    static func positions(for canvas: CGSize) -> [CGPoint] {
        referenceSeatPositions.map { transform($0, to: canvas) }
    }

    private static let referenceSeatPositions: [CGPoint] = [
        .init(x: 218, y: 75),
        .init(x: 451, y: 72),
        .init(x: 670, y: 74),
        .init(x: 828, y: 202),
        .init(x: 82, y: 170),
        .init(x: 82, y: 269),
        .init(x: 201, y: 340),
        .init(x: 337, y: 348),
        .init(x: 476, y: 350),
    ]

    static func referenceScale(for canvas: CGSize) -> CGFloat {
        min(canvas.width / referenceCanvas.width, canvas.height / referenceCanvas.height)
    }

    private static func referenceOrigin(for canvas: CGSize) -> CGPoint {
        let scale = referenceScale(for: canvas)
        return CGPoint(
            x: (canvas.width - referenceCanvas.width * scale) / 2,
            y: (canvas.height - referenceCanvas.height * scale) / 2
        )
    }

    private static func transform(_ point: CGPoint, to canvas: CGSize) -> CGPoint {
        let scale = referenceScale(for: canvas)
        let origin = referenceOrigin(for: canvas)
        return CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
    }

    private static func transform(_ rect: CGRect, to canvas: CGSize) -> CGRect {
        let scale = referenceScale(for: canvas)
        let origin = referenceOrigin(for: canvas)
        return CGRect(
            x: origin.x + rect.minX * scale,
            y: origin.y + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    static func tableSurfaceFrame(for canvas: CGSize) -> CGRect {
        transform(CGRect(x: 65, y: 73, width: 760, height: 292), to: canvas)
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
        transform(CGRect(x: 30, y: 10, width: 862, height: 44), to: canvas)
    }

    static func centerBoardRegion(for canvas: CGSize) -> CGRect {
        transform(CGRect(x: 300, y: 140, width: 320, height: 164), to: canvas)
    }

    static func betControlRegion(for canvas: CGSize) -> CGRect {
        transform(CGRect(x: 624, y: 296, width: 265, height: 112), to: canvas)
    }

    static func communityCardFrames(for canvas: CGSize) -> [CGRect] {
        let board = centerBoardRegion(for: canvas)
        let totalWidth = communityCardSize.width * 5 + holeCardSpacing * 4
        let startX = board.midX - totalWidth / 2
        let y = board.minY + 25

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
        let width = min(180 * referenceScale(for: canvas), board.width - 16)
        return CGRect(
            x: board.midX - width / 2,
            y: board.minY + 1,
            width: width,
            height: currentHandHeight * referenceScale(for: canvas)
        )
    }

    static func potFrame(for canvas: CGSize) -> CGRect {
        let board = centerBoardRegion(for: canvas)
        let slotBottom = communityCardFrames(for: canvas).map(\.maxY).max() ?? board.minY
        return CGRect(
            x: board.midX - potSize.width / 2,
            y: slotBottom + 2,
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

    static func chipFlightPosition(
        from start: CGPoint,
        to end: CGPoint,
        progress: CGFloat,
        arcOffset: CGFloat
    ) -> CGPoint {
        let progress = min(max(progress, 0), 1)
        guard start != end else { return start }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let control = CGPoint(
            x: midpoint.x - dy / length * arcOffset,
            y: midpoint.y + dx / length * arcOffset
        )
        let remaining = 1 - progress
        return CGPoint(
            x: remaining * remaining * start.x
                + 2 * remaining * progress * control.x
                + progress * progress * end.x,
            y: remaining * remaining * start.y
                + 2 * remaining * progress * control.y
                + progress * progress * end.y
        )
    }
}

struct PokerSeatView: View {
    let seat: TableSeatState
    let secondsRemaining: Int?
    let isWinner: Bool
    let reduceMotion: Bool
    let animation: TableAnimationPresentation

    var body: some View {
        Group {
            if seat.isHuman {
                humanSeatContent
            } else {
                robotSeatContent
            }
        }
        .foregroundStyle(RCTheme.primaryText)
        .frame(
            width: PokerTableLayout.seatSize.width,
            height: PokerTableLayout.seatSize.height
        )
        .shadow(
            color: isWinner || seat.isCurrentActor ? RCTheme.gold.opacity(0.30) : .clear,
            radius: 8
        )
        .opacity(seat.hasFolded ? 0.48 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    private var robotSeatContent: some View {
        HStack(alignment: .center, spacing: 4) {
            avatar(size: 48)

            VStack(alignment: .leading, spacing: 1) {
                holeCards
                seatIdentityLine
                seatChipLine
                seatStatusLine
            }
        }
        .padding(.horizontal, 3)
    }

    private var humanSeatContent: some View {
        VStack(spacing: 1) {
            holeCards
            HStack(spacing: 4) {
                avatar(size: 50)
                VStack(alignment: .leading, spacing: 1) {
                    seatIdentityLine
                    seatChipLine
                    seatStatusLine
                }
            }
        }
    }

    private func avatar(size: CGFloat) -> some View {
        RobotAvatarView(
            imageName: seat.avatarAssetName,
            fallbackText: seat.displayName,
            size: size
        )
        .accessibilityIdentifier(
            seat.isHuman
                ? "table.localAvatar"
                : "table.botAvatar.\(seat.id.rawValue)"
        )
        .accessibilityValue(seat.displayName)
    }

    private var holeCards: some View {
        HStack(spacing: PokerTableLayout.holeCardSpacing) {
            ForEach(0..<2, id: \.self) { index in
                TableCardView(
                    cardState: seat.cards.indices.contains(index)
                        ? seat.cards[index]
                        : .faceDown
                )
                .frame(width: holeCardSize.width, height: holeCardSize.height)
                .accessibilityIdentifier(
                    seat.isHuman ? "table.localHoleCard" : "table.botHoleCard"
                )
            }
        }
        .frame(height: holeCardSize.height)
        .scaleEffect(holeCardScale)
    }

    private var seatIdentityLine: some View {
        Text(seat.displayName)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var seatChipLine: some View {
        HStack(spacing: 4) {
            CasinoChipPileView(
                amount: seat.stack.rawValue,
                scale: 0.62,
                showsAmount: false,
                stackCount: 2
            )
            .frame(width: 34, height: 22)
            Text(CasinoChipAmountPresentation.text(for: seat.stack.rawValue))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(RCTheme.primaryText)
                .lineLimit(1)
        }
        .frame(height: 23, alignment: .leading)
    }

    @ViewBuilder
    private var seatStatusLine: some View {
        if showsStatus {
            Text(statusText)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(RCTheme.gold)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.62), in: Capsule())
                .accessibilityIdentifier("table.seatStatus.\(seat.id.rawValue)")
        }
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
