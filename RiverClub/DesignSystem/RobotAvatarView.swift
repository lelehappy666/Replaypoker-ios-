import SwiftUI
import UIKit

struct RobotAvatarView: View {
    let imageName: String?
    let fallbackText: String
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(fallbackText.prefix(2)))
                    .font(.caption.bold())
                    .foregroundStyle(RCTheme.primaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RCTheme.surfaceRaised)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(RCTheme.gold.opacity(0.72), lineWidth: 1) }
        .accessibilityLabel(fallbackText)
    }

    private var avatarImage: UIImage? {
        let resolvedName = imageName
            ?? RobotIdentityCatalog.all.first(where: {
                $0.displayName == fallbackText
            })?.avatarAssetName
            ?? (fallbackText == "RiverAce"
                ? RobotIdentityCatalog.all.first?.avatarAssetName
                : nil)
        guard let resolvedName else { return nil }
        return UIImage(named: resolvedName)
    }
}
