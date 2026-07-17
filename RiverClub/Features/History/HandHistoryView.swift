import PokerCore
import PokerSession
import SwiftUI

enum HandHistoryEmptyPresentation {
    static let noRecordsMessage = "完成一局后会在这里保存牌局记录"
    static let filteredMessage = "当前筛选条件下没有牌局"
}

struct HandHistoryLayout: Equatable {
    let filterWidth: CGFloat
    let contentWidth: CGFloat
    let minimumRowHeight: CGFloat

    static func safeCanvas(width: CGFloat, height _: CGFloat) -> Self {
        let filterWidth: CGFloat
        if width < 680 {
            filterWidth = 168
        } else if width < 800 {
            filterWidth = 184
        } else {
            filterWidth = 220
        }
        let horizontalPadding: CGFloat = 40
        let spacing: CGFloat = 16
        return Self(
            filterWidth: filterWidth,
            contentWidth: max(0, width - horizontalPadding - spacing - filterWidth),
            minimumRowHeight: 88
        )
    }

    static func rowMetrics(contentWidth: CGFloat) -> HandHistoryRowLayout {
        if contentWidth < 440 {
            return HandHistoryRowLayout(
                titleWidth: 105,
                cardSize: CGSize(width: 26, height: 37),
                horizontalSpacing: 4,
                horizontalPadding: 8,
                minimumSpacerWidth: 2,
                deltaWidth: 112,
                potLineLimit: 2
            )
        }
        if contentWidth < 520 {
            return HandHistoryRowLayout(
                titleWidth: 115,
                cardSize: CGSize(width: 28, height: 40),
                horizontalSpacing: 6,
                horizontalPadding: 8,
                minimumSpacerWidth: 4,
                deltaWidth: 112,
                potLineLimit: 2
            )
        }
        return HandHistoryRowLayout(
            titleWidth: 145,
            cardSize: CGSize(width: 30, height: 41),
            horizontalSpacing: 12,
            horizontalPadding: 16,
            minimumSpacerWidth: 8,
            deltaWidth: 130,
            potLineLimit: 1
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
    let potLineLimit: Int

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

struct HandHistoryFilterPanelLayout: Equatable {
    let canvasHeight: CGFloat
    let minimumContentHeight: CGFloat
    let minimumControlHeight: CGFloat
    let usesVerticalScrolling: Bool

    static func metrics(
        canvasHeight: CGFloat,
        dynamicTypeSize: DynamicTypeSize
    ) -> Self {
        let minimumContentHeight: CGFloat = dynamicTypeSize.isAccessibilitySize
            ? 520
            : 340
        let minimumControlHeight: CGFloat = dynamicTypeSize.isAccessibilitySize
            ? 68
            : 44
        return Self(
            canvasHeight: canvasHeight,
            minimumContentHeight: minimumContentHeight,
            minimumControlHeight: minimumControlHeight,
            usesVerticalScrolling: minimumContentHeight > canvasHeight
        )
    }
}

struct HandHistoryView: View {
    @Bindable var session: AppSession

    var body: some View {
        historyContent
    }

    @ViewBuilder
    private var historyContent: some View {
        if let detail = session.handHistoryState.selection {
            HandHistoryDetailView(
                detail: detail,
                onBack: session.closeHandHistoryDetail,
                onDelete: {
                    session.requestDeleteHand(id: detail.id)
                }
            )
        } else {
            historyList
        }
    }

    private var historyList: some View {
        GeometryReader { proxy in
            let layout = HandHistoryLayout.safeCanvas(
                width: proxy.size.width,
                height: proxy.size.height
            )
            HStack(spacing: 16) {
                HandHistoryFilterPanel(
                    balance: session.chipBalance,
                    filters: session.handHistoryState.filters,
                    availableTables: session.handHistoryState.availableTables,
                    canDeleteAll: session.handHistoryState.canDeleteAll,
                    onChange: session.updateHandHistoryFilters,
                    onBeginCustomDate: session.beginCustomHandHistoryDateSelection,
                    onChangeCustomDate: { date, calendar in
                        try? session.selectCustomHandHistoryDate(
                            date,
                            calendar: calendar
                        )
                    },
                    onDeleteAll: session.requestDeleteAllHistory
                )
                .frame(width: layout.filterWidth)

                HandHistoryContent(
                    state: session.handHistoryState,
                    onSelect: session.selectHandHistory,
                    onScrollTargetChange: session.updateHandHistoryScrollTarget,
                    onRetry: session.loadHandHistory,
                    onResetFilters: {
                        session.updateHandHistoryFilters(HandHistoryFilters())
                    }
                )
                .frame(width: layout.contentWidth)
            }
            .frame(maxHeight: .infinity)
            .padding(6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.list")
    }

}

struct HandHistoryDeletionLayout: Equatable {
    let minimumContentHeight: CGFloat
    let usesVerticalScrolling: Bool
    let stacksActionsVertically: Bool

    static func metrics(
        canvasHeight: CGFloat,
        dynamicTypeSize: DynamicTypeSize
    ) -> Self {
        let minimumContentHeight: CGFloat = dynamicTypeSize.isAccessibilitySize
            ? 520
            : 260
        return Self(
            minimumContentHeight: minimumContentHeight,
            usesVerticalScrolling: minimumContentHeight > canvasHeight,
            stacksActionsVertically: dynamicTypeSize.isAccessibilitySize
        )
    }
}

struct HandHistoryDeletionConfirmationView: View {
    let presentation: HandHistoryDeletionOverlay
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            let layout = HandHistoryDeletionLayout.metrics(
                canvasHeight: proxy.size.height,
                dynamicTypeSize: dynamicTypeSize
            )
            ZStack {
                Color.black.opacity(0.68)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())

                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        if !layout.usesVerticalScrolling { Spacer(minLength: 0) }
                        confirmationCard(layout: layout)
                        if !layout.usesVerticalScrolling { Spacer(minLength: 0) }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: layout.usesVerticalScrolling
                            ? layout.minimumContentHeight
                            : proxy.size.height
                    )
                }
                .scrollDisabled(!layout.usesVerticalScrolling)
                .scrollIndicators(layout.usesVerticalScrolling ? .visible : .hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            perform(presentation.escapeAction)
        }
        .accessibilityIdentifier("history.deletionConfirmation")
    }

    private func confirmationCard(
        layout: HandHistoryDeletionLayout
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(RCTheme.primaryText)
                Text(presentation.message)
                    .font(.body)
                    .foregroundStyle(RCTheme.secondaryText)
            }
            actions(layout: layout)
        }
        .padding(24)
        .frame(maxWidth: 440)
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

    @ViewBuilder
    private func actions(layout: HandHistoryDeletionLayout) -> some View {
        if layout.stacksActionsVertically {
            VStack(spacing: 12) {
                cancelButton
                confirmButton
            }
        } else {
            HStack(spacing: 12) {
                cancelButton
                Spacer(minLength: 0)
                confirmButton
            }
        }
    }

    private var cancelButton: some View {
        Button(role: .cancel, action: onCancel) {
            Text("取消").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(
            HandHistoryDeletionPresentation.cancelDeleteIdentifier
        )
    }

    private var confirmButton: some View {
        Button(role: .destructive, action: onConfirm) {
            Text(presentation.confirmationTitle).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .accessibilityIdentifier(presentation.confirmationIdentifier)
    }

    private func perform(_ action: HandHistoryDeletionDismissAction) {
        switch action {
        case .cancel:
            onCancel()
        }
    }
}

private struct HandHistoryFilterPanel: View {
    let balance: Int
    let filters: HandHistoryFilters
    let availableTables: [HandHistoryTableOption]
    let canDeleteAll: Bool
    let onChange: (HandHistoryFilters) -> Void
    let onBeginCustomDate: () -> Void
    let onChangeCustomDate: (Date, Calendar) -> Void
    let onDeleteAll: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.calendar) private var calendar

    var body: some View {
        GeometryReader { proxy in
            let layout = HandHistoryFilterPanelLayout.metrics(
                canvasHeight: proxy.size.height,
                dynamicTypeSize: dynamicTypeSize
            )
            ScrollView(.vertical) {
                controls(minimumControlHeight: layout.minimumControlHeight)
                    .padding(16)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: layout.minimumContentHeight,
                        alignment: .topLeading
                    )
            }
            .scrollDisabled(!layout.usesVerticalScrolling)
            .scrollIndicators(layout.usesVerticalScrolling ? .visible : .hidden)
        }
        .background(RCTheme.surface.opacity(0.90), in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: RCTheme.corner)
                .stroke(RCTheme.gold.opacity(0.18), lineWidth: 1)
        }
    }

    private func controls(minimumControlHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("牌局存档")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(RCTheme.primaryText)
                Text("$\(balance.formatted())")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(RCTheme.gold)
                    .accessibilityLabel("娱乐筹码 \(balance.formatted())")
                    .accessibilityIdentifier("history.balance")
            }

            Divider().overlay(RCTheme.gold.opacity(0.24))

            filterLabel("日期")
            Menu {
                Button("全部日期") { changeDate(.all) }
                Button("今天") { changeDate(.today) }
                Button("最近 7 天") { changeDate(.lastSevenDays) }
                Button("自定义日期…", action: onBeginCustomDate)
            } label: {
                filterControl(
                    title: dateTitle,
                    systemImage: "calendar",
                    minimumHeight: minimumControlHeight
                )
            }
            .accessibilityIdentifier("history.filter.date")

            if case let .custom(day) = filters.dateSelection {
                DatePicker(
                    "自定义日期",
                    selection: customDateBinding(for: day),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .frame(minHeight: minimumControlHeight)
                .accessibilityIdentifier("history.filter.customDate")
            }

            filterLabel("牌桌")
            Menu {
                Button("全部牌桌") { changeTable(nil) }
                ForEach(availableTables) { table in
                    Button(table.name) { changeTable(table.id) }
                }
            } label: {
                filterControl(
                    title: tableTitle,
                    systemImage: "rectangle.on.rectangle",
                    minimumHeight: minimumControlHeight
                )
            }
            .accessibilityIdentifier("history.filter.table")

            Button(role: .destructive, action: onDeleteAll) {
                Label("清空全部存档", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canDeleteAll)
            .accessibilityIdentifier("history.deleteAll")
        }
    }

    private func filterLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(RCTheme.secondaryText)
    }

    private func filterControl(
        title: String,
        systemImage: String,
        minimumHeight: CGFloat
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
        }
        .foregroundStyle(RCTheme.primaryText)
        .padding(.horizontal, 12)
        .frame(minHeight: minimumHeight)
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

    private func customDateBinding(for day: LocalDay) -> Binding<Date> {
        Binding(
            get: {
                (try? HandHistoryCustomDatePolicy.date(
                    for: day,
                    calendar: calendar
                )) ?? Date()
            },
            set: { onChangeCustomDate($0, calendar) }
        )
    }
}

private struct HandHistoryContent: View {
    let state: HandHistoryViewState
    let onSelect: (HandID) -> Void
    let onScrollTargetChange: (HandID?) -> Void
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
            statusPanel(
                title: HandHistoryEmptyPresentation.noRecordsMessage,
                systemImage: "tray"
            ) {
                EmptyView()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("history.empty")
        } else {
            statusPanel(
                title: HandHistoryEmptyPresentation.filteredMessage,
                systemImage: "line.3.horizontal.decrease.circle"
            ) {
                Button("清除筛选", action: onResetFilters)
                    .buttonStyle(.bordered)
            }
            .accessibilityElement(children: .contain)
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
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(
                id: Binding(
                    get: { state.listScrollTarget },
                    set: { onScrollTargetChange($0) }
                ),
                anchor: .top
            )
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
        .background(RCTheme.surface.opacity(0.90), in: RoundedRectangle(cornerRadius: RCTheme.corner))
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(item.completedAtText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(RCTheme.secondaryText)
                    Text(item.blindsText)
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

                VStack(alignment: .trailing, spacing: 5) {
                    Text(item.humanChipDeltaText)
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(deltaColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(item.allocatedPotTotalText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(RCTheme.secondaryText)
                        .lineLimit(layout.potLineLimit)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.trailing)
                }
                .frame(width: layout.deltaWidth, alignment: .trailing)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: 88)
            .contentShape(Rectangle())
            .background(RCTheme.surface.opacity(0.90), in: RoundedRectangle(cornerRadius: RCTheme.corner))
            .overlay {
                RoundedRectangle(cornerRadius: RCTheme.corner)
                    .stroke(RCTheme.gold.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history.row.\(item.id.rawValue)")
        .accessibilityLabel(
            "\(item.tableName)，第 \(item.handNumber) 手，\(item.blindsText)，完成时间 \(item.completedAtText)，净变化 \(item.humanChipDeltaText)，\(item.allocatedPotTotalText)"
        )
    }

    private var deltaColor: Color {
        guard let delta = item.humanChipDelta else { return RCTheme.secondaryText }
        if delta > 0 { return .green }
        if delta < 0 { return .orange }
        return RCTheme.secondaryText
    }
}
