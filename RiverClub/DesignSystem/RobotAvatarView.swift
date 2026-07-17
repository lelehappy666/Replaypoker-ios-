import SwiftUI
import UIKit

struct RobotAvatarView: View {
    let imageName: String?
    let fallbackText: String
    let size: CGFloat

    var body: some View {
        Group {
            if let imageName, UIImage(named: imageName) != nil {
                Image(imageName)
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
}
