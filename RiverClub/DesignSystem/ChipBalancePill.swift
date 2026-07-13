import SwiftUI

struct ChipBalancePill: View {
    let balance: Int
    var body: some View {
        Label(balance.formatted(), systemImage: "circle.fill")
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(RCTheme.gold)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RCTheme.surface, in: Capsule())
            .accessibilityLabel("娱乐筹码 \(balance)")
    }
}
