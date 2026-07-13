import SwiftUI

enum MotionPolicy {
    static func shouldAnimate(reduceMotion: Bool) -> Bool { !reduceMotion }
}

struct AppRootView: View {
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let repository: any PokerRepository = MockPokerRepository()
    @State private var pendingBuyInTable: PokerTableSummary?
    @State private var tableSeatState: LoadableState<[PokerSeat]> = .loading
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
                            LoadableContent(
                                state: tableSeatState,
                                hasActiveFilters: false,
                                isEmpty: { $0.count != 9 },
                                emptyTitle: "牌桌座位数据不完整",
                                emptyDescription: "请重试后再继续牌局。",
                                onRetry: { Task { await loadTableSeats() } },
                                onClearFilters: {}
                            ) { seats in
                                PokerTableView(
                                    table: table,
                                    seats: seats,
                                    session: session,
                                    onExit: { session.leaveTable(returningTo: tableReturnRoute) }
                                )
                            }
                            .task(id: table.id) { await loadTableSeats() }
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
                    .transition(MotionPolicy.shouldAnimate(reduceMotion: reduceMotion) ? .opacity : .identity)
                    .zIndex(1)
            }
        }
        .background(RCTheme.background)
        .preferredColorScheme(.dark)
        .animation(
            MotionPolicy.shouldAnimate(reduceMotion: reduceMotion)
                ? .easeOut(duration: 0.16)
                : nil,
            value: pendingBuyInTable
        )
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

    @MainActor
    private func loadTableSeats() async {
        let cached = tableSeatState.content
        if cached == nil { tableSeatState = .loading }
        do {
            let seats = try await repository.seats()
            guard seats.count == 9 else { throw TableSeatLoadError.incomplete }
            tableSeatState = .loaded(seats)
        } catch {
            tableSeatState = cached == nil
                ? .failed(message: "无法加载牌桌座位，请重试。")
                : .offline(cached: cached)
        }
    }
}

private enum TableSeatLoadError: Error { case incomplete }
