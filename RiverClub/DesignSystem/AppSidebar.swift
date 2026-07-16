import SwiftUI

struct AppSidebar: View {
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
                        .padding(.horizontal, 16)
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
        .padding(16)
        .frame(width: 220)
        .background(RCTheme.surface)
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
