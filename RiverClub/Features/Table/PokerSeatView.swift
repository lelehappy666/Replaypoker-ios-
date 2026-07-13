import SwiftUI

enum PokerTableLayout {
    static let normalizedCenters: [CGPoint] = [
        .init(x: 0.25, y: 0.16), .init(x: 0.50, y: 0.10), .init(x: 0.75, y: 0.16),
        .init(x: 0.88, y: 0.34), .init(x: 0.86, y: 0.62), .init(x: 0.18, y: 0.68),
        .init(x: 0.12, y: 0.48), .init(x: 0.14, y: 0.27), .init(x: 0.50, y: 0.86),
    ]

    static func positions(for _: CGSize) -> [CGPoint] {
        normalizedCenters
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
        .frame(width: 104)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(seat.isLocalPlayer ? "本人" : "玩家")\(seat.name)，娱乐筹码 \(seat.chips)\(isActing ? "，行动中，剩余 18 秒" : seat.status.map { "，\($0)" } ?? "")")
    }
}
