import SwiftUI

struct LobbyView: View {
    let repository: any PokerRepository
    let balance: Int
    let onQuickJoin: (PokerTableSummary) -> Void
    let onAllTables: () -> Void

    @State private var loadState: LoadableState<LobbySnapshot> = .loading
    @State private var category: LobbyCategory = .recommended
    @State private var quickBlind: CommonBlindLevel = .oneHundredTwoHundred
    @State private var joinStatusMessage: String?

    var body: some View {
        ZStack {
            LobbyBackground()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("晚上好，RiverAce")
                            .font(.largeTitle.weight(.bold))
                        Text("挑一张喜欢的桌子，享受一局轻松牌局。")
                            .foregroundStyle(RCTheme.secondaryText)
                    }
                    Spacer()
                    Button(action: {}) {
                        Image(systemName: "bell")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("通知")
                    ChipBalancePill(balance: balance)
                }

                LoadableContent(
                    state: loadState,
                    hasActiveFilters: category != .recommended,
                    isEmpty: { snapshot in
                        snapshot.tables.filter(category.includes).isEmpty
                            && (category != .recommended || snapshot.featuredTable == nil)
                    },
                    emptyTitle: "没有符合条件的牌桌",
                    emptyDescription: "当前没有可加入的牌桌。",
                    onRetry: { Task { await loadLobby() } },
                    onClearFilters: { category = .recommended }
                ) { _ in
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("大厅分类", selection: $category) {
                                ForEach(LobbyCategory.allCases) { item in
                                    Text(item.rawValue).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(minHeight: 44)

                            quickJoinControls

                            if category == .recommended, let featuredTable {
                                featuredCard(featuredTable)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(category == .recommended ? "热门牌桌" : category.rawValue)
                                    .font(.title3.weight(.bold))
                                Spacer()
                                Button("查看全部", action: onAllTables)
                                    .buttonStyle(.bordered)
                                    .tint(RCTheme.gold)
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("lobby.allTables")
                            }

                            if let joinStatusMessage {
                                Label(joinStatusMessage, systemImage: "person.2.badge.clock")
                                    .font(.subheadline)
                                    .foregroundStyle(RCTheme.secondaryText)
                                    .accessibilityLabel(joinStatusMessage)
                            }

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12),
                                ],
                                spacing: 12
                            ) {
                                ForEach(categoryTables.prefix(2)) { table in
                                    LobbyHotTableCard(
                                        table: table,
                                        onJoin: { onQuickJoin(table) },
                                        onWaitlist: { waitlist(table) }
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .foregroundStyle(RCTheme.primaryText)
        .safeAreaPadding(24)
        .task { await loadLobby() }
    }

    private var quickJoinControls: some View {
        HStack(spacing: 12) {
            Picker("常用盲注", selection: $quickBlind) {
                ForEach(CommonBlindLevel.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 190, minHeight: 44)

            Button("匹配空位") {
                if let table = QuickJoinMatcher.match(in: tables, blind: quickBlind) {
                    joinStatusMessage = nil
                    onQuickJoin(table)
                } else {
                    joinStatusMessage = "当前盲注没有空位，已留在大厅。"
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(RCTheme.gold)
            .foregroundStyle(RCTheme.background)
            .frame(minHeight: 44)
            .accessibilityIdentifier("lobby.quickJoin")
            .accessibilityHint("按所选盲注匹配一张有空位的牌桌")
        }
    }

    private var categoryTables: [PokerTableSummary] {
        tables.filter(category.includes)
    }

    private var tables: [PokerTableSummary] {
        loadState.content?.tables ?? []
    }

    private var featuredTable: PokerTableSummary? {
        loadState.content?.featuredTable
    }

    private func featuredCard(_ table: PokerTableSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("为你推荐")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(RCTheme.gold)
                    Text(table.name)
                        .font(.title.weight(.bold))
                    Text("无限注德州扑克 · 盲注 \(table.smallBlind.formatted()) / \(table.bigBlind.formatted())")
                        .foregroundStyle(RCTheme.secondaryText)
                }
                Spacer()
                joinButton(for: table)
            }

            HStack(alignment: .bottom, spacing: 16) {
                Text(
                    "当前 \(table.players) / \(table.capacity) 人 · 平均底池 \(EntertainmentAmountFormatter.string(table.averagePot))"
                )
                .font(.subheadline.monospacedDigit())

                Spacer(minLength: 12)

                HStack(spacing: -8) {
                    ForEach(RobotIdentityCatalog.preview(for: table.id, count: 6)) { identity in
                        RobotAvatarView(
                            imageName: identity.avatarAssetName,
                            fallbackText: identity.displayName,
                            size: 42
                        )
                        .accessibilityLabel("\(identity.displayName)，\(identity.accessibilityDescription)")
                        .accessibilityIdentifier("lobby.recommendedAvatar")
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .padding(22)
        .background(RCTheme.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: RCTheme.corner)
                .stroke(RCTheme.gold.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .accessibilityIdentifier("lobby.recommendedCard")
    }

    @ViewBuilder
    private func joinButton(for table: PokerTableSummary) -> some View {
        Button(table.hasOpenSeat ? "立即入桌" : "加入候补") {
            if table.hasOpenSeat {
                onQuickJoin(table)
            } else {
                waitlist(table)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(RCTheme.gold)
        .foregroundStyle(RCTheme.background)
        .controlSize(.large)
        .frame(minHeight: 44)
        .accessibilityLabel(
            table.hasOpenSeat
                ? "\(table.name)，立即入桌"
                : "\(table.name)，满桌，加入候补"
        )
        .accessibilityHint(
            table.hasOpenSeat
                ? "打开买入确认"
                : "加入候补并留在大厅"
        )
    }

    private func waitlist(_ table: PokerTableSummary) {
        joinStatusMessage = "已加入「\(table.name)」候补，仍留在大厅。"
    }

    @MainActor
    private func loadLobby() async {
        let cached = loadState.content
        if cached == nil { loadState = .loading }
        do {
            async let featured = repository.featuredTable()
            async let allTables = repository.tables()
            loadState = .loaded(
                LobbySnapshot(
                    featuredTable: try await featured,
                    tables: try await allTables
                )
            )
        } catch {
            loadState = cached == nil
                ? .failed(message: "请检查网络连接后重试。")
                : .offline(cached: cached)
        }
    }
}

private struct LobbyHotTableCard: View {
    let table: PokerTableSummary
    let onJoin: () -> Void
    let onWaitlist: () -> Void

    var body: some View {
        Button(action: table.hasOpenSeat ? onJoin : onWaitlist) {
            VStack(alignment: .leading, spacing: 10) {
                Text(table.name)
                    .font(.headline.weight(.bold))
                Text("无限注德州扑克 · 盲注 \(table.smallBlind.formatted()) / \(table.bigBlind.formatted())")
                    .font(.caption)
                    .foregroundStyle(RCTheme.secondaryText)
                Text("当前 \(table.players) / \(table.capacity) 人 · 平均底池 \(EntertainmentAmountFormatter.string(table.averagePot))")
                    .font(.subheadline.monospacedDigit())
                HStack(spacing: -7) {
                    ForEach(RobotIdentityCatalog.preview(for: table.id, count: 3)) { identity in
                        RobotAvatarView(
                            imageName: identity.avatarAssetName,
                            fallbackText: identity.displayName,
                            size: 30
                        )
                        .accessibilityLabel("\(identity.displayName)，\(identity.accessibilityDescription)")
                    }
                }
                .accessibilityElement(children: .contain)
                Text(table.hasOpenSeat ? "加入" : "候补")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(RCTheme.gold)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(18)
        .background(RCTheme.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: RCTheme.corner)
                .stroke(RCTheme.gold.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        .accessibilityIdentifier("lobby.hotTable")
        .accessibilityLabel("\(table.name)，\(table.hasOpenSeat ? "有空位，加入" : "满桌，候补")")
    }
}

private struct LobbySnapshot {
    let featuredTable: PokerTableSummary?
    let tables: [PokerTableSummary]
}
