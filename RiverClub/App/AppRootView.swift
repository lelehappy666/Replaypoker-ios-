import SwiftUI

struct AppRootView: View {
    @Bindable var session: AppSession
    private let repository: any PokerRepository = MockPokerRepository()
    @State private var selectedTable: PokerTableSummary?

    var body: some View {
        NavigationStack {
            Group {
                switch session.route {
                case .login:
                    LoginView(
                        onAppleLogin: session.continueAsGuest,
                        onGuestLogin: session.continueAsGuest
                    )
                case .table:
                    featurePlaceholder(for: .table)
                case .lobby, .tournaments, .tables, .profile:
                    HStack(spacing: 0) {
                        AppSidebar(selection: session.route, onSelect: session.open)
                        routedSidebarContent
                    }
                }
            }
        }
        .background(RCTheme.background)
        .preferredColorScheme(.dark)
        .sheet(item: $selectedTable) { table in
            BuyInSheet(
                table: table,
                balance: session.chipBalance,
                onConfirm: { amount, _ in
                    session.chipBalance -= amount
                    selectedTable = nil
                    session.open(.table)
                },
                onCancel: { selectedTable = nil }
            )
            .presentationDetents([.large])
        }
    }

    @ViewBuilder
    private var routedSidebarContent: some View {
        switch session.route {
        case .lobby:
            LobbyView(
                repository: repository,
                balance: session.chipBalance,
                onQuickJoin: { selectedTable = $0 },
                onAllTables: { session.open(.tables) }
            )
        case .tables:
            TableListView(repository: repository) { selectedTable = $0 }
        case .tournaments, .profile:
            featurePlaceholder(for: session.route)
        case .login, .table:
            EmptyView()
        }
    }

    private func featurePlaceholder(for route: AppRoute) -> some View {
        Text(title(for: route))
            .font(.title.weight(.semibold))
            .foregroundStyle(RCTheme.primaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func title(for route: AppRoute) -> String {
        switch route {
        case .login: "登录"
        case .lobby: "游戏大厅"
        case .tables: "牌桌列表"
        case .table: "已进入牌桌"
        case .tournaments: "锦标赛"
        case .profile: "个人中心"
        }
    }
}
