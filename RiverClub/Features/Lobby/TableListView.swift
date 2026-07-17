import SwiftUI

struct TableListView: View {
    let repository: any PokerRepository
    let onSelect: (PokerTableSummary) -> Void

    @State private var loadState: LoadableState<[PokerTableSummary]> = .loading
    @State private var filters = TableListFilters()
    @State private var joinStatusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("全部牌桌")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(RCTheme.primaryText)

            Picker("主筛选", selection: $filters.primary) {
                ForEach(TablePrimaryFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)

            HStack(spacing: 12) {
                filterMenu("桌型", selection: $filters.tableType, values: TableTypeFilter.allCases)
                filterMenu(
                    "空位",
                    selection: $filters.seatAvailability,
                    values: SeatAvailabilityFilter.allCases
                )
                filterMenu("盲注范围", selection: $filters.blindRange, values: BlindRangeFilter.allCases)
                Spacer()
            }

            if let joinStatusMessage {
                Label(joinStatusMessage, systemImage: "person.2.badge.clock")
                    .font(.subheadline)
                    .foregroundStyle(RCTheme.secondaryText)
                    .accessibilityLabel(joinStatusMessage)
            }

            tableContent
        }
        .safeAreaPadding(24)
        .task { await loadTables() }
    }

    @ViewBuilder
    private var tableContent: some View {
        LoadableContent(
            state: loadState,
            hasActiveFilters: filters != TableListFilters(),
            isEmpty: { filters.apply(to: $0).isEmpty },
            emptyTitle: "没有符合条件的牌桌",
            emptyDescription: "清除筛选后再看看。",
            onRetry: { Task { await loadTables() } },
            onClearFilters: { filters = TableListFilters() }
        ) { tables in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filters.apply(to: tables)) { table in
                        TableRow(
                            table: table,
                            onJoin: { onSelect(table) },
                            onWaitlist: {
                                joinStatusMessage = "已加入「\(table.name)」候补，仍留在牌桌列表。"
                            }
                        )
                    }
                }
            }
        }
    }

    private func filterMenu<Value: RawRepresentable & Identifiable & Hashable>(
        _ title: String,
        selection: Binding<Value>,
        values: [Value]
    ) -> some View where Value.RawValue == String {
        Picker(title, selection: selection) {
            ForEach(values) { value in
                Text("\(title)：\(value.rawValue)").tag(value)
            }
        }
        .pickerStyle(.menu)
        .buttonStyle(.bordered)
        .tint(RCTheme.gold)
        .frame(minHeight: 44)
        .accessibilityLabel(title)
    }

    @MainActor
    private func loadTables() async {
        let cached = loadState.content
        if cached == nil { loadState = .loading }
        do {
            loadState = .loaded(try await repository.tables())
        } catch {
            loadState = cached == nil
                ? .failed(message: "请检查网络连接后重试。")
                : .offline(cached: cached)
        }
    }
}

struct TableRow: View {
    let table: PokerTableSummary
    let onJoin: () -> Void
    let onWaitlist: () -> Void

    var body: some View {
        Button(action: table.hasOpenSeat ? onJoin : onWaitlist) {
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
                    Text("无限注德州扑克 · 九人桌")
                        .font(.caption)
                        .foregroundStyle(RCTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Metric(label: "盲注", value: "\(table.smallBlind.formatted()) / \(table.bigBlind.formatted())")
                Metric(label: "玩家", value: "\(table.players) / \(table.capacity)")
                Metric(
                    label: "平均底池",
                    value: EntertainmentAmountFormatter.string(table.averagePot)
                )

                Text(table.hasOpenSeat ? "加入" : "候补")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(RCTheme.gold)
                    .frame(minWidth: 56)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .background(RCTheme.surface, in: RoundedRectangle(cornerRadius: RCTheme.corner))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tableRow.\(table.id.uuidString)")
        .accessibilityLabel(
            table.hasOpenSeat
                ? "\(table.name)，有空位，加入"
                : "\(table.name)，满桌，候补"
        )
        .accessibilityHint(
            table.hasOpenSeat
                ? "打开买入确认"
                : "加入候补并留在当前列表"
        )
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
