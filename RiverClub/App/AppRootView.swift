import SwiftUI

struct AppRootView: View {
    @Bindable var session: AppSession
    private let repository: any PokerRepository = MockPokerRepository()
    @State private var pendingBuyInTable: PokerTableSummary?
    @State private var tableSeats: [PokerSeat] = []
    @State private var tableReturnRoute: AppRoute = .lobby

    var body: some View {
        ZStack {
            NavigationStack {
                Group {
                    switch session.route {
                    case .login:
                        LoginView(
                            onAppleLogin: session.continueAsGuest,
                            onGuestLogin: session.continueAsGuest
                        )
                    case .table:
                        if let table = session.selectedTable {
                            PokerTableView(
                                table: table,
                                seats: tableSeats,
                                session: session,
                                onExit: { session.leaveTable(returningTo: tableReturnRoute) }
                            )
                            .task {
                                tableSeats = (try? await repository.seats()) ?? []
                            }
                        }
                    case .lobby, .tournaments, .tables, .profile:
                        HStack(spacing: 0) {
                            AppSidebar(selection: session.route, onSelect: session.open)
                            routedSidebarContent
                        }
                    }
                }
            }

            if let pendingBuyInTable {
                buyInOverlay(for: pendingBuyInTable)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .background(RCTheme.background)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.16), value: pendingBuyInTable)
    }

    @ViewBuilder
    private var routedSidebarContent: some View {
        switch session.route {
        case .lobby:
            LobbyView(
                repository: repository,
                balance: session.chipBalance,
                onQuickJoin: openBuyInIfJoinable,
                onAllTables: { session.open(.tables) }
            )
        case .tables:
            TableListView(repository: repository, onSelect: openBuyInIfJoinable)
        case .tournaments:
            TournamentsView(repository: repository)
        case .profile:
            ProfileView(repository: repository)
        case .login, .table:
            EmptyView()
        }
    }

    private func buyInOverlay(for table: PokerTableSummary) -> some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .onTapGesture { pendingBuyInTable = nil }

            BuyInSheet(
                table: table,
                balance: session.chipBalance,
                onConfirm: { amount, _ in
                    session.chipBalance -= amount
                    pendingBuyInTable = nil
                    session.enterTable(table)
                },
                onCancel: { pendingBuyInTable = nil }
            )
            .frame(maxWidth: 620, maxHeight: 360)
            .padding(.horizontal, 36)
            .padding(.vertical, 16)
        }
        .safeAreaPadding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("买入确认弹窗")
    }

    private func openBuyInIfJoinable(_ table: PokerTableSummary) {
        guard JoinDisposition(table: table) == .buyIn else { return }
        tableReturnRoute = session.route
        pendingBuyInTable = table
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
