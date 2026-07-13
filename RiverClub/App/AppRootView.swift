import SwiftUI

struct AppRootView: View {
    @Bindable var session: AppSession

    var body: some View {
        Group {
            switch session.route {
            case .login:
                Text("River Club Login")
            case .table:
                featurePlaceholder(for: .table)
            case .lobby, .tournaments, .tables, .profile:
                HStack(spacing: 0) {
                    AppSidebar(selection: session.route, onSelect: session.open)
                    featurePlaceholder(for: session.route)
                }
            }
        }
        .background(RCTheme.background)
        .preferredColorScheme(.dark)
    }

    private func featurePlaceholder(for route: AppRoute) -> some View {
        Text(title(for: route))
            .font(.title.weight(.semibold))
            .foregroundStyle(RCTheme.primaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func title(for route: AppRoute) -> String {
        switch route {
        case .login: "River Club Login"
        case .lobby: "Lobby"
        case .tables: "Tables"
        case .table: "Table"
        case .tournaments: "Tournaments"
        case .profile: "Profile"
        }
    }
}
