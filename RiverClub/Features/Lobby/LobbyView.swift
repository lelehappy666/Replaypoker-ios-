import SwiftUI

struct LobbyView: View {
    let repository: any PokerRepository
    let balance: Int
    let onQuickJoin: (PokerTableSummary) -> Void
    let onAllTables: () -> Void

    @State private var featuredTable: PokerTableSummary?
    @State private var tables: [PokerTableSummary] = []
    @State private var category: LobbyCategory = .recommended
    @State private var quickBlind: CommonBlindLevel = .oneHundredTwoHundred
    @State private var joinStatusMessage: String?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
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

            if isLoading {
                ProgressView("正在准备大厅…")
                    .tint(RCTheme.gold)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("大厅暂时离线", systemImage: "wifi.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await loadLobby() } }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
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

                        ForEach(categoryTables.prefix(3)) { table in
                            TableRow(
                                table: table,
                                onJoin: { onQuickJoin(table) },
                                onWaitlist: { waitlist(table) }
                            )
                        }
                    }
                }
            }
        }
        .foregroundStyle(RCTheme.primaryText)
        .safeAreaPadding(24)
        .task { await loadLobby() }
    }

    private var quickJoinControls: some View {
        HStack(spacing: 12) {
            Text("快速加入")
                .font(.headline)

            Picker("常用盲注", selection: $quickBlind) {
                ForEach(CommonBlindLevel.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 430, minHeight: 44)

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

    private func featuredCard(_ table: PokerTableSummary) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("为你推荐")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RCTheme.gold)
                Text(table.name)
                    .font(.title.weight(.bold))
                Text("无限注德州扑克 · 盲注 \(table.smallBlind.formatted()) / \(table.bigBlind.formatted())")
                    .foregroundStyle(RCTheme.secondaryText)
                Text("当前 \(table.players) / \(table.capacity) 人 · 平均底池 \(table.averagePot.formatted())")
                    .font(.subheadline.monospacedDigit())
            }
            Spacer()
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
        .padding(22)
        .background(
            LinearGradient(
                colors: [RCTheme.surfaceRaised, RCTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: RCTheme.corner)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RCTheme.corner)
                .stroke(RCTheme.gold.opacity(0.3), lineWidth: 1)
        }
    }

    private func waitlist(_ table: PokerTableSummary) {
        joinStatusMessage = "已加入「\(table.name)」候补，仍留在大厅。"
    }

    @MainActor
    private func loadLobby() async {
        isLoading = true
        errorMessage = nil
        do {
            async let featured = repository.featuredTable()
            async let allTables = repository.tables()
            featuredTable = try await featured
            tables = try await allTables
        } catch {
            errorMessage = "请检查网络连接后重试。"
        }
        isLoading = false
    }
}
