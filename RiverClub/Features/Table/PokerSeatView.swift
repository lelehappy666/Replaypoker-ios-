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

enum PokerTablePresentation {
    static func title(for table: PokerTableSummary) -> String {
        "\(table.name) · \(table.smallBlind.formatted()) / \(table.bigBlind.formatted())"
    }
}

struct PokerSeatView: View {
    let seat: PokerSeat
    var isActing = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(seat.isLocalPlayer ? RCTheme.gold.opacity(0.24) : RCTheme.surfaceRaised)

                Text(seat.initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(seat.isLocalPlayer ? RCTheme.gold : RCTheme.primaryText)
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())
            .fixedSize()
            .overlay {
                Circle()
                    .stroke(isActing ? RCTheme.gold : RCTheme.secondaryText.opacity(0.55), lineWidth: isActing ? 3 : 2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(
                seat.isLocalPlayer ? "table.localAvatar" : "table.avatar.\(seat.position)"
            )

            ViewThatFits(in: .horizontal) {
                Text(seat.name)
                Text(seat.initials)
            }
            .font(.caption2.weight(.semibold))
            .lineLimit(1)

            Text(seat.chips.formatted())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(RCTheme.gold)

            if isActing || seat.status != nil {
                Text(isActing ? "行动中 · 18秒" : seat.status ?? "")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(RCTheme.background)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RCTheme.gold, in: Capsule())
            }
        }
        .foregroundStyle(RCTheme.primaryText)
        .frame(width: PokerTableLayout.seatSize.width, height: PokerTableLayout.seatSize.height, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(seat.isLocalPlayer ? "本人" : "玩家")\(seat.name)，娱乐筹码 \(seat.chips)\(isActing ? "，行动中，剩余 18 秒" : seat.status.map { "，\($0)" } ?? "")")
    }
}
