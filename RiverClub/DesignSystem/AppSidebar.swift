import SwiftUI

struct AppRouteBackground: View {
    let route: AppRoute

    var body: some View {
        ZStack {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .overlay(RCTheme.background.opacity(overlayOpacity))
                .overlay {
                    LinearGradient(
                        colors: [
                            .black.opacity(0.30),
                            RCTheme.background.opacity(0.12),
                            .black.opacity(0.42),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

            if route == .tournaments {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 210, weight: .ultraLight))
                    .foregroundStyle(RCTheme.gold.opacity(0.055))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 24)
            }
        }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    private var assetName: String {
        switch route {
        case .tournaments: "tournament-background"
        case .tables: "history-background"
        case .profile: "profile-background"
        case .lobby, .tableBrowser, .table: "lobby-background"
        case .login: "login-background"
        }
    }

    private var overlayOpacity: Double {
        switch route {
        case .tables, .profile: 0.42
        default: 0.34
        }
    }
}

struct AppSidebar: View {
    static let landscapePhoneWidth: CGFloat = 176
    static let shellVerticalPadding: CGFloat = 14
    static let minimumSafeInset: CGFloat = 10
    static let contentGap: CGFloat = 16
    static let horizontalPadding: CGFloat = 10

    let selection: AppRoute
    let onSelect: (AppRoute) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(AppRoute.sidebarRoutes.indices, id: \.self) { index in
                let route = AppRoute.sidebarRoutes[index]
                Button {
                    onSelect(route)
                } label: {
                    Label(route.sidebarLabel, systemImage: route.sidebarSystemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Self.horizontalPadding)
                        .padding(.vertical, 12)
                        .foregroundStyle(selection == route ? RCTheme.gold : RCTheme.primaryText)
                        .background(
                            selection == route ? RCTheme.surfaceRaised : Color.clear,
                            in: RoundedRectangle(cornerRadius: RCTheme.corner)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.\(route.sidebarIdentifier)")
            }

            Spacer()
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 14)
        .frame(width: Self.landscapePhoneWidth)
        .frame(maxHeight: .infinity)
        .background(
            RCTheme.surface.opacity(0.88),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(RCTheme.gold.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
    }
}

private extension AppRoute {
    var sidebarLabel: String {
        switch self {
        case .lobby: "游戏大厅"
        case .tournaments: "锦标赛"
        case .tables: "我的牌局"
        case .profile: "个人中心"
        case .login, .tableBrowser, .table: ""
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .lobby: "house.fill"
        case .tournaments: "trophy.fill"
        case .tables: "suit.club.fill"
        case .profile: "person.crop.circle.fill"
        case .login, .tableBrowser, .table: ""
        }
    }

    var sidebarIdentifier: String {
        switch self {
        case .lobby: "lobby"
        case .tournaments: "tournaments"
        case .tables: "tables"
        case .profile: "profile"
        case .login: "login"
        case .tableBrowser: "tableBrowser"
        case .table: "table"
        }
    }
}
