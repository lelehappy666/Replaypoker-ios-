import SwiftUI

struct BetControlBar: View {
    let callAmount: Int
    let onFold: () -> Void
    let onCall: () -> Void
    let onRaise: (Int) -> Void

    @State private var raiseAmount = 2_400.0

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                presetButton("半池", amount: 1_800)
                presetButton("四分之三池", amount: 2_700)
                Text(raiseAmount.formatted(.number.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(RCTheme.gold)
                    .frame(minWidth: 52, alignment: .trailing)
            }

            Slider(value: $raiseAmount, in: 800...8_000, step: 200)
                .tint(RCTheme.gold)
                .frame(width: 250)
                .accessibilityLabel("加注娱乐筹码")

            HStack(spacing: 8) {
                actionButton("弃牌", tint: RCTheme.surfaceRaised, foreground: RCTheme.primaryText, identifier: "action.fold", action: onFold)
                actionButton("跟注 \(callAmount.formatted())", tint: RCTheme.surfaceRaised, foreground: RCTheme.primaryText, identifier: "action.call", action: onCall)
                actionButton("加注", tint: RCTheme.gold, foreground: RCTheme.background, identifier: "action.raise") {
                    onRaise(Int(raiseAmount))
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: RCTheme.corner))
    }

    private func presetButton(_ title: String, amount: Double) -> some View {
        Button(title) { raiseAmount = amount }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(RCTheme.gold)
            .frame(minHeight: 44)
    }

    private func actionButton(
        _ title: String,
        tint: Color,
        foreground: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.bold))
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .foregroundStyle(foreground)
            .frame(minWidth: 82, minHeight: 44)
            .accessibilityIdentifier(identifier)
    }
}
