import SwiftUI

struct TableErrorPanel: View {
    let message: String
    let retryTitle: String
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)

            Button(retryTitle, action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(RCTheme.gold)
                .foregroundStyle(RCTheme.background)
                .disabled(isRetrying)
                .accessibilityIdentifier("action.retrySave")
        }
        .padding(12)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table.saveError")
    }
}
