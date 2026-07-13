import SwiftUI

struct LobbyView: View {
    let repository: any PokerRepository
    let balance: Int
    let onQuickJoin: (PokerTableSummary) -> Void
    let onAllTables: () -> Void

    @State private var featuredTable: PokerTableSummary?
    @State private var tables: [PokerTableSummary] = []
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
                        if let featuredTable {
                            featuredCard(featuredTable)
                        }

                        HStack {
                            Text("热门牌桌")
                                .font(.title3.weight(.bold))
                            Spacer()
                            Button("查看全部", action: onAllTables)
                                .buttonStyle(.bordered)
                                .tint(RCTheme.gold)
                                .accessibilityIdentifier("lobby.allTables")
                        }

                        ForEach(tables.prefix(3)) { table in
                            TableRow(table: table) { onQuickJoin(table) }
                        }
                    }
                }
            }
        }
        .foregroundStyle(RCTheme.primaryText)
        .safeAreaPadding(24)
        .task { await loadLobby() }
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
            Button("快速加入") { onQuickJoin(table) }
                .buttonStyle(.borderedProminent)
                .tint(RCTheme.gold)
                .foregroundStyle(RCTheme.background)
                .controlSize(.large)
                .accessibilityIdentifier("lobby.quickJoin")
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
