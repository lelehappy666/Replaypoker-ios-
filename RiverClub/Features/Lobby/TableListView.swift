import SwiftUI

struct TableListView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case low = "低盲注"
        case medium = "中盲注"
        case high = "高盲注"
        case favorites = "收藏"

        var id: Self { self }
    }

    let repository: any PokerRepository
    let onSelect: (PokerTableSummary) -> Void

    @State private var tables: [PokerTableSummary] = []
    @State private var filter: Filter = .all
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("全部牌桌")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(RCTheme.primaryText)

            Picker("盲注筛选", selection: $filter) {
                ForEach(Filter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            tableContent
        }
        .safeAreaPadding(24)
        .task { await loadTables() }
    }

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("正在加载牌桌…")
                .tint(RCTheme.gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("暂时无法连接", systemImage: "wifi.slash")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重试") { Task { await loadTables() } }
            }
            .foregroundStyle(RCTheme.primaryText)
        } else if filteredTables.isEmpty {
            ContentUnavailableView {
                Label("没有符合条件的牌桌", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("清除筛选后再看看。")
            } actions: {
                Button("清除筛选") { filter = .all }
            }
            .foregroundStyle(RCTheme.primaryText)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredTables) { table in
                        TableRow(table: table) { onSelect(table) }
                    }
                }
            }
        }
    }

    private var filteredTables: [PokerTableSummary] {
        tables.filter { table in
            switch filter {
            case .all: true
            case .low: table.bigBlind <= 200
            case .medium: table.bigBlind > 200 && table.bigBlind < 1_000
            case .high: table.bigBlind >= 1_000
            case .favorites: table.isFavorite
            }
        }
    }

    @MainActor
    private func loadTables() async {
        isLoading = true
        errorMessage = nil
        do {
            tables = try await repository.tables()
        } catch {
            errorMessage = "请检查网络连接后重试。"
        }
        isLoading = false
    }
}

struct TableRow: View {
    let table: PokerTableSummary
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(table.name)
                            .font(.headline)
                        if table.isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(RCTheme.gold)
                                .accessibilityLabel("已收藏")
                        }
                    }
                    Text("无限注德州扑克")
                        .font(.caption)
                        .foregroundStyle(RCTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Metric(label: "盲注", value: "\(table.smallBlind.formatted()) / \(table.bigBlind.formatted())")
                Metric(label: "玩家", value: "\(table.players) / \(table.capacity)")
                Metric(label: "平均底池", value: table.averagePot.formatted())

                Text(table.players < table.capacity ? "加入" : "候补")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(RCTheme.gold)
                    .frame(minWidth: 56)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(RCTheme.surface, in: RoundedRectangle(cornerRadius: RCTheme.corner))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tableRow.\(table.id.uuidString)")
    }
}

private struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(RCTheme.secondaryText)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(RCTheme.primaryText)
        }
        .frame(minWidth: 94, alignment: .leading)
    }
}
