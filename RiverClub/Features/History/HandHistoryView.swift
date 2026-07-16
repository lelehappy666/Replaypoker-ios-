import PokerCore
import PokerSession
import SwiftUI

struct HandHistoryLayout: Equatable {
    let filterWidth: CGFloat
    let contentWidth: CGFloat
    let minimumRowHeight: CGFloat

    static func safeCanvas(width: CGFloat, height _: CGFloat) -> Self {
        let filterWidth: CGFloat = 220
        let horizontalPadding: CGFloat = 40
        let spacing: CGFloat = 16
        return Self(
            filterWidth: filterWidth,
            contentWidth: max(0, width - horizontalPadding - spacing - filterWidth),
            minimumRowHeight: 88
        )
    }

    static func rowMetrics(contentWidth: CGFloat) -> HandHistoryRowLayout {
        if contentWidth < 520 {
            return HandHistoryRowLayout(
                titleWidth: 128,
                cardSize: CGSize(width: 28, height: 40),
                horizontalSpacing: 8,
                horizontalPadding: 12,
                minimumSpacerWidth: 4,
                deltaWidth: 72
            )
        }
        return HandHistoryRowLayout(
            titleWidth: 150,
            cardSize: CGSize(width: 30, height: 41),
            horizontalSpacing: 14,
            horizontalPadding: 16,
            minimumSpacerWidth: 8,
            deltaWidth: 76
        )
    }
}

struct HandHistoryRowLayout: Equatable {
    let titleWidth: CGFloat
    let cardSize: CGSize
    let horizontalSpacing: CGFloat
    let horizontalPadding: CGFloat
    let minimumSpacerWidth: CGFloat
    let deltaWidth: CGFloat

    var minimumWidth: CGFloat {
        let fiveCardsWidth = cardSize.width * 5 + 4 * 4
        return titleWidth
            + fiveCardsWidth
            + deltaWidth
            + minimumSpacerWidth
            + horizontalSpacing * 3
            + horizontalPadding * 2
    }
}

struct HandHistoryView: View {
    @Bindable var session: AppSession

    var body: some View {
        Group {
            if let detail = session.handHistoryState.selection {
                HandHistoryDetailView(
                    detail: detail,
                    onBack: session.closeHandHistoryDetail,
                    onDelete: {}
                )
            } else {
                historyList
            }
        }
        .background(RCTheme.background.ignoresSafeArea())
    }

    private var historyList: some View {
        HStack(spacing: 16) {
            HandHistoryFilterPanel(
                balance: session.chipBalance,
                filters: session.handHistoryState.filters,
                availableTables: session.handHistoryState.availableTables,
                onChange: session.updateHandHistoryFilters,
                onDeleteAll: {}
            )
            .frame(width: 220)

            HandHistoryContent(
                state: session.handHistoryState,
                onSelect: session.selectHandHistory,
                onRetry: session.loadHandHistory,
                onResetFilters: {
                    session.updateHandHistoryFilters(HandHistoryFilters())
                }
            )
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.list")
        .onAppear { session.loadHandHistory() }
    }
}

private struct HandHistoryFilterPanel: View {
    let balance: Int
    let filters: HandHistoryFilters
    let availableTables: [HandHistoryTableOption]
    let onChange: (HandHistoryFilters) -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("牌局存档")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(RCTheme.primaryText)
                Label("娱乐筹码 \(balance.formatted())", systemImage: "circle.fill")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(RCTheme.gold)
                    .accessibilityIdentifier("history.balance")
            }

            Divider().overlay(RCTheme.gold.opacity(0.24))

            filterLabel("日期")
            Menu {
                Button("全部日期") { changeDate(.all) }
                Button("今天") { changeDate(.today) }
                Button("最近 7 天") { changeDate(.lastSevenDays) }
            } label: {
                filterControl(title: dateTitle, systemImage: "calendar")
            }
            .accessibilityIdentifier("history.filter.date")

            filterLabel("牌桌")
            Menu {
                Button("全部牌桌") { changeTable(nil) }
                ForEach(availableTables) { table in
                    Button(table.name) { changeTable(table.id) }
                }
            } label: {
                filterControl(title: tableTitle, systemImage: "rectangle.on.rectangle")
            }
            .accessibilityIdentifier("history.filter.table")

            Spacer(minLength: 8)

            Button(role: .destructive, action: onDeleteAll) {
                Label("清空全部存档", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("history.deleteAll")
        }
        .padding(16)
        .background(RCTheme.surface, in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: RCTheme.corner)
                .stroke(RCTheme.gold.opacity(0.18), lineWidth: 1)
        }
    }

    private func filterLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(RCTheme.secondaryText)
    }

    private func filterControl(title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
        }
        .foregroundStyle(RCTheme.primaryText)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RCTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
    }

    private var dateTitle: String {
        switch filters.dateSelection {
        case .all: "全部日期"
        case .today: "今天"
        case .lastSevenDays: "最近 7 天"
        case let .custom(day): day.rawValue
        }
    }

    private var tableTitle: String {
        guard let tableID = filters.table else { return "全部牌桌" }
        return availableTables.first(where: { $0.id == tableID })?.name
            ?? "牌桌 \(tableID.rawValue)"
    }

    private func changeDate(_ dateSelection: HandHistoryDateSelection) {
        onChange(
            HandHistoryFilters(table: filters.table, dateSelection: dateSelection)
        )
    }

    private func changeTable(_ table: TableID?) {
        onChange(
            HandHistoryFilters(table: table, dateSelection: filters.dateSelection)
        )
    }
}

private struct HandHistoryContent: View {
    let state: HandHistoryViewState
    let onSelect: (HandID) -> Void
    let onRetry: () -> Void
    let onResetFilters: () -> Void

    var body: some View {
        Group {
            switch state.loadState {
            case .idle, .loading:
                loadingRows
            case let .loaded(items):
                if items.isEmpty {
                    emptyState
                } else {
                    historyRows(items)
                }
            case let .failed(message):
                statusPanel(
                    title: message,
                    systemImage: "exclamationmark.triangle.fill"
                ) {
                    Button("重试", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(RCTheme.gold)
                        .foregroundStyle(RCTheme.background)
                        .accessibilityIdentifier("history.retry")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: RCTheme.corner)
                    .fill(RCTheme.surface)
                    .frame(minHeight: 88)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(RCTheme.surfaceRaised)
                            .frame(width: 180, height: 14)
                            .padding(16)
                    }
            }
            Spacer(minLength: 0)
        }
        .accessibilityLabel("正在加载牌局存档")
    }

    @ViewBuilder
    private var emptyState: some View {
        if state.filters == HandHistoryFilters() {
            statusPanel(title: "还没有完成的牌局存档", systemImage: "tray") {
                EmptyView()
            }
            .accessibilityIdentifier("history.empty")
        } else {
            statusPanel(title: "当前筛选没有结果", systemImage: "line.3.horizontal.decrease.circle") {
                Button("清除筛选", action: onResetFilters)
                    .buttonStyle(.bordered)
            }
            .accessibilityIdentifier("history.filteredEmpty")
        }
    }

    private func historyRows(_ items: [HandHistoryListItem]) -> some View {
        GeometryReader { proxy in
            let rowLayout = HandHistoryLayout.rowMetrics(
                contentWidth: proxy.size.width
            )
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        HandHistoryRow(item: item, layout: rowLayout) {
                            onSelect(item.id)
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
        }
    }

    private func statusPanel<Actions: View>(
        title: String,
        systemImage: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(RCTheme.gold)
            Text(title)
                .font(.headline)
                .foregroundStyle(RCTheme.primaryText)
            actions()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RCTheme.surface, in: RoundedRectangle(cornerRadius: RCTheme.corner))
    }
}

private struct HandHistoryRow: View {
    let item: HandHistoryListItem
    let layout: HandHistoryRowLayout
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: layout.horizontalSpacing) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(item.tableName) · 第 \(item.handNumber) 手")
                        .font(.headline)
                        .foregroundStyle(RCTheme.primaryText)
                    Text(item.localDay.rawValue)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(RCTheme.secondaryText)
                }
                .frame(width: layout.titleWidth, alignment: .leading)

                HStack(spacing: 4) {
                    ForEach(Array(item.communityCards.enumerated()), id: \.offset) { _, card in
                        TableCardView(card: card)
                            .frame(
                                width: layout.cardSize.width,
                                height: layout.cardSize.height
                            )
                    }
                }

                Spacer(minLength: layout.minimumSpacerWidth)

                Text(deltaText)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(deltaColor)
                    .frame(width: layout.deltaWidth, alignment: .trailing)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: 88)
            .contentShape(Rectangle())
            .background(RCTheme.surface, in: RoundedRectangle(cornerRadius: RCTheme.corner))
            .overlay {
                RoundedRectangle(cornerRadius: RCTheme.corner)
                    .stroke(RCTheme.gold.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history.row.\(item.id.rawValue)")
        .accessibilityLabel("\(item.tableName)，第 \(item.handNumber) 手，净变化 \(deltaText)")
    }

    private var deltaText: String {
        guard let delta = item.humanChipDelta else { return "0" }
        if delta > 0 { return "+\(delta.formatted())" }
        if delta < 0 { return "−\((-delta).formatted())" }
        return "0"
    }

    private var deltaColor: Color {
        guard let delta = item.humanChipDelta else { return RCTheme.secondaryText }
        if delta > 0 { return .green }
        if delta < 0 { return .orange }
        return RCTheme.secondaryText
    }
}
