import SwiftUI

enum MotionPolicy {
    static func shouldAnimate(reduceMotion: Bool) -> Bool { !reduceMotion }
}

struct AppRootModalPolicy: Equatable {
    let allowsBackgroundInteraction: Bool
    let hidesBackgroundFromAccessibility: Bool

    init(
        isHistoryDeletionPresented: Bool,
        isTableDeparturePresented: Bool = false,
        isAbandonedSettlementPresented: Bool = false
    ) {
        let isModalPresented = isHistoryDeletionPresented
            || isTableDeparturePresented
            || isAbandonedSettlementPresented
        allowsBackgroundInteraction = !isModalPresented
        hidesBackgroundFromAccessibility = isModalPresented
    }
}

struct AppRootView: View {
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let repository: any PokerRepository = MockPokerRepository()
    @State private var pendingBuyInTable: PokerTableSummary?
    @State private var buyInError: String?

    var body: some View {
        let deletionOverlay = HandHistoryDeletionPresentation.overlay(
            for: session.handHistoryState
        )
        let modalPolicy = AppRootModalPolicy(
            isHistoryDeletionPresented: deletionOverlay != nil,
            isTableDeparturePresented: session.isTableDeparturePresented,
            isAbandonedSettlementPresented: session.hasUnsettledCashSession
        )
        ZStack {
            appShell
                .allowsHitTesting(modalPolicy.allowsBackgroundInteraction)
                .accessibilityHidden(
                    modalPolicy.hidesBackgroundFromAccessibility
                )

            if let deletionOverlay {
                HandHistoryDeletionConfirmationView(
                    presentation: deletionOverlay,
                    onConfirm: confirmHistoryDeletion,
                    onCancel: session.cancelHistoryDeletion
                )
                .zIndex(3)
            }

            if session.isTableDeparturePresented {
                TableDepartureConfirmationView(
                    isLeaving: session.isLeavingTable,
                    errorMessage: session.tableDepartureError,
                    onConfirm: {
                        Task { await session.confirmTableDeparture() }
                    },
                    onCancel: session.cancelTableDeparture
                )
                .zIndex(4)
            }

            if session.hasUnsettledCashSession {
                AbandonedCashSessionSettlementView(
                    isSettling: session.isSettlingAbandonedCashSession,
                    errorMessage: session.abandonedCashSessionError,
                    onRetry: {
                        Task {
                            await session.retryAbandonedCashSessionSettlement()
                        }
                    }
                )
                .zIndex(5)
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
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await session.resumeTableForLifecycle() }
            case .inactive, .background:
                session.suspendTableForLifecycle()
            @unknown default:
                session.suspendTableForLifecycle()
            }
        }
        .task {
            await session.settleAbandonedCashSessionIfNeeded()
        }
    }

    private var appShell: some View {
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
                        if let coordinator = session.tableCoordinator,
                           let table = session.selectedTable {
                            PokerTableView(
                                coordinator: coordinator,
                                table: table,
                                balance: session.chipBalance,
                                sendIntent: session.sendTableIntent,
                                onRequestLeave: session.requestTableDeparture
                            )
                        }
                    case .lobby, .tournaments, .tables, .tableBrowser, .profile:
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

            if session.route == .table,
               let presentation = TableStartupRecoveryPresentation(
                   errorMessage: session.tableStartupError
               ) {
                TableStartupRecoveryView(
                    presentation: presentation,
                    onRetry: {
                        Task { await session.startOrResumeTableHand() }
                    }
                )
                .zIndex(2)
            }
        }
    }

    @ViewBuilder
    private var routedSidebarContent: some View {
        switch session.route {
        case .lobby:
            LobbyView(
                repository: repository,
                balance: session.chipBalance,
                onQuickJoin: openBuyInIfJoinable,
                onAllTables: { session.open(.tableBrowser) }
            )
        case .tables:
            HandHistoryView(session: session)
        case .tableBrowser:
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
                .onTapGesture { closeBuyIn() }

            BuyInSheet(
                table: table,
                balance: session.chipBalance,
                errorMessage: buyInError,
                onConfirm: { amount, autoTopUp in
                    do {
                        try session.joinCashTable(
                            table,
                            buyIn: amount,
                            autoTopUp: autoTopUp,
                            reduceMotion: reduceMotion
                        )
                        buyInError = nil
                        pendingBuyInTable = nil
                        #if DEBUG
                        if uiTestingPayoutScenarioIsActive {
                            Task { await session.playUITestingPayoutScenarioIfRequested() }
                        } else {
                            Task { await session.startOrResumeTableHand() }
                        }
                        #else
                        Task { await session.startOrResumeTableHand() }
                        #endif
                    } catch {
                        buyInError = "买入失败，请重试。"
                    }
                },
                onCancel: closeBuyIn
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
        buyInError = nil
        pendingBuyInTable = table
    }

    private func closeBuyIn() {
        buyInError = nil
        pendingBuyInTable = nil
    }

    private func confirmHistoryDeletion() {
        do {
            try session.confirmHistoryDeletion()
        } catch {
            // AppSession 保留 pending、列表、详情和可重试的中文错误。
        }
    }

}

#if DEBUG
private var uiTestingPayoutScenarioIsActive: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    guard arguments.contains("-uiTesting"),
          let flag = arguments.firstIndex(of: "-uiTestingPayoutScenario"),
          arguments.indices.contains(flag + 1)
    else { return false }
    return ["single", "split"].contains(arguments[flag + 1])
}
#endif

private struct AbandonedCashSessionSettlementView: View {
    let isSettling: Bool
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 16) {
                Text("正在处理上次牌桌")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(RCTheme.primaryText)
                Text("完成安全结算并返还剩余娱乐筹码后，即可重新买入。")
                    .foregroundStyle(RCTheme.secondaryText)

                if isSettling || errorMessage == nil {
                    ProgressView("正在结算…")
                        .tint(RCTheme.gold)
                        .foregroundStyle(RCTheme.primaryText)
                        .accessibilityIdentifier("abandonedSettlement.progress")
                } else if let errorMessage {
                    Label(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)

                    Button("重试结算", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(RCTheme.gold)
                        .foregroundStyle(RCTheme.background)
                        .accessibilityIdentifier("abandonedSettlement.retry")
                }
            }
            .padding(24)
            .frame(maxWidth: 440, alignment: .leading)
            .background(
                RCTheme.surfaceRaised,
                in: RoundedRectangle(cornerRadius: RCTheme.corner)
            )
            .overlay {
                RoundedRectangle(cornerRadius: RCTheme.corner)
                    .stroke(RCTheme.gold.opacity(0.28), lineWidth: 1)
            }
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("abandonedSettlement.modal")
    }
}

private struct TableDepartureConfirmationView: View {
    let isLeaving: Bool
    let errorMessage: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("确认离开牌桌？")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(RCTheme.primaryText)
                    Text("当前手牌将自动弃牌，结算完成后带走剩余筹码。")
                        .foregroundStyle(RCTheme.secondaryText)
                }

                if isLeaving {
                    ProgressView("正在结算并离桌…")
                        .tint(RCTheme.gold)
                        .foregroundStyle(RCTheme.primaryText)
                        .accessibilityIdentifier("table.leave.progress")
                } else {
                    if let errorMessage {
                        Label(
                            errorMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    }

                    HStack {
                        Button("继续游戏", action: onCancel)
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("table.leave.cancel")

                        Spacer()

                        Button(
                            errorMessage == nil ? "弃牌并离桌" : "重试离桌",
                            role: .destructive,
                            action: onConfirm
                        )
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .accessibilityIdentifier(
                            errorMessage == nil
                                ? "table.leave.confirm"
                                : "table.leave.retry"
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 460)
            .background(
                RCTheme.surfaceRaised,
                in: RoundedRectangle(cornerRadius: RCTheme.corner)
            )
            .overlay {
                RoundedRectangle(cornerRadius: RCTheme.corner)
                    .stroke(RCTheme.gold.opacity(0.28), lineWidth: 1)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            guard !isLeaving else { return }
            onCancel()
        }
        .accessibilityIdentifier("table.leave.confirmation")
    }
}

struct TableStartupRecoveryPresentation: Equatable {
    let message: String
    let retryTitle = "重试牌局"

    init?(errorMessage: String?) {
        guard let errorMessage else { return nil }
        message = errorMessage
    }
}

private struct TableStartupRecoveryView: View {
    let presentation: TableStartupRecoveryPresentation
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Label(
                presentation.message,
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            Button(presentation.retryTitle, action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(RCTheme.gold)
                .foregroundStyle(RCTheme.background)
                .accessibilityIdentifier("table.startupRetry")
        }
        .padding(24)
        .background(
            RCTheme.surfaceRaised,
            in: RoundedRectangle(cornerRadius: RCTheme.corner)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RCTheme.corner)
                .stroke(RCTheme.gold.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .padding(32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table.startupError")
    }
}
