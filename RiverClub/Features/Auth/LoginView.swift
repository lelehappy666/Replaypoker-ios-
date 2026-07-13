import SwiftUI

struct LoginView: View {
    let onAppleLogin: () -> Void
    let onGuestLogin: () -> Void

    var body: some View {
        HStack(spacing: 48) {
            VStack(alignment: .leading, spacing: 18) {
                Text("RIVER CLUB")
                    .font(.caption.weight(.bold))
                    .tracking(4)
                    .foregroundStyle(RCTheme.gold)

                Text("欢迎来到河畔牌局")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(RCTheme.primaryText)

                Text("使用无现金价值的娱乐筹码，随时加入一桌轻松的德州扑克。")
                    .font(.body)
                    .foregroundStyle(RCTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onAppleLogin) {
                    Label("使用 Apple 登录", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(RCTheme.gold)
                .foregroundStyle(RCTheme.background)
                .controlSize(.large)
                .accessibilityIdentifier("login.apple")

                Button("游客快速体验", action: onGuestLogin)
                    .buttonStyle(.bordered)
                    .tint(RCTheme.gold)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("login.guest")

                Text("继续即表示你同意用户协议与隐私政策，并确认已达到适用年龄要求。")
                    .font(.caption)
                    .foregroundStyle(RCTheme.secondaryText)
            }
            .frame(maxWidth: 420, alignment: .leading)

            ZStack {
                RoundedRectangle(cornerRadius: 40)
                    .fill(RCTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 40)
                            .stroke(RCTheme.gold.opacity(0.35), lineWidth: 1)
                    }

                Image(systemName: "suit.club.fill")
                    .font(.system(size: 150, weight: .light))
                    .foregroundStyle(RCTheme.gold)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 12)

                Text("只为娱乐 · 无现金价值")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RCTheme.secondaryText)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(28)
            }
            .frame(maxWidth: .infinity, maxHeight: 300)
        }
        .safeAreaPadding(.horizontal, 42)
        .safeAreaPadding(.vertical, 26)
    }
}
