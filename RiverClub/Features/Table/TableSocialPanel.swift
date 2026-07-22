import SwiftUI

enum TableSocialPanelMode: Equatable {
    case messages
    case reactions
}

struct TableSocialPanel: View {
    let mode: TableSocialPanelMode
    let onSend: (TableSocialContent) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(mode == .messages ? "快捷聊天" : "表情")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RCTheme.gold)
                Spacer()
                Button("关闭", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(RCTheme.secondaryText)
            }

            LazyVGrid(columns: columns, spacing: 7) {
                if mode == .messages {
                    ForEach(TableQuickMessage.allCases) { message in
                        socialButton(message.text) {
                            onSend(.message(message))
                        }
                    }
                } else {
                    ForEach(TableReaction.allCases) { reaction in
                        socialButton(reaction.text) {
                            onSend(.reaction(reaction))
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 250)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(RCTheme.gold.opacity(0.42), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table.socialPanel")
    }

    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func socialButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .foregroundStyle(RCTheme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(RCTheme.surface.opacity(0.96), in: Capsule())
            .buttonStyle(.plain)
    }
}
