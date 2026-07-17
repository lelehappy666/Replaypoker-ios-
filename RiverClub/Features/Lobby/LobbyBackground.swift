import SwiftUI

struct LobbyBackground: View {
    var body: some View {
        Image("lobby-background")
            .resizable()
            .scaledToFill()
            .overlay(RCTheme.background.opacity(0.80))
            .overlay {
                RadialGradient(
                    colors: [
                        RCTheme.surfaceRaised.opacity(0.36),
                        .black.opacity(0.54),
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: 620
                )
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
