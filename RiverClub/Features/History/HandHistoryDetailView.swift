import PokerCore
import SwiftUI

enum HandHistoryDetailLayout {
    struct SeatSlot: Identifiable, Equatable {
        let id: Int
        let cardSize: CGSize
        let frame: CGRect
    }

    struct Metrics: Equatable {
        let canvasSize: CGSize
        let contentPadding: CGFloat
        let columnSpacing: CGFloat
        let rowSpacing: CGFloat
        let columnCount: Int
        let seatMinimumHeight: CGFloat
        let cardSize: CGSize

        var seatSlots: [SeatSlot] {
            let contentWidth = max(0, canvasSize.width - contentPadding * 2)
            let seatWidth = max(
                0,
                (contentWidth - columnSpacing * CGFloat(columnCount - 1))
                    / CGFloat(columnCount)
            )
            return (0..<9).map { id in
                let column = id % columnCount
                let row = id / columnCount
                return SeatSlot(
                    id: id,
                    cardSize: cardSize,
                    frame: CGRect(
                        x: contentPadding
                            + CGFloat(column) * (seatWidth + columnSpacing),
                        y: CGFloat(row) * (seatMinimumHeight + rowSpacing),
                        width: seatWidth,
                        height: seatMinimumHeight
                    )
                )
            }
        }
    }

    static func metrics(in size: CGSize) -> Metrics {
        let contentPadding: CGFloat = 20
        let columnSpacing: CGFloat = 8
        let contentWidth = max(0, size.width - contentPadding * 2)
        let seatWidth = max(0, (contentWidth - columnSpacing * 2) / 3)
        let cardWidth = max(28, min(34, (seatWidth - 112) / 2))
        let cardHeight = max(40, cardWidth * 46 / 34)
        return Metrics(
            canvasSize: size,
            contentPadding: contentPadding,
            columnSpacing: columnSpacing,
            rowSpacing: 8,
            columnCount: 3,
            seatMinimumHeight: 76,
            cardSize: CGSize(width: cardWidth, height: cardHeight)
        )
    }
}

struct HandHistoryDetailView: View {
    let detail: HandHistoryDetail
    let onBack: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = HandHistoryDetailLayout.metrics(in: proxy.size)
            ScrollView {
                VStack(spacing: 12) {
                    HandHistoryDetailHeader(
                        detail: detail,
                        onBack: onBack,
                        onDelete: onDelete
                    )
                    HandHistoryCommunityCards(cards: detail.communityCards)
                    HandHistorySeatGrid(seats: detail.seats, layout: layout)
                    HandHistoryPotList(
                        pots: detail.pots,
                        returns: detail.uncalledReturns
                    )
                }
                .padding(layout.contentPadding)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.detail")
    }
}

private struct HandHistoryDetailHeader: View {
    let detail: HandHistoryDetail
    let onBack: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("返回", systemImage: "chevron.left", action: onBack)
                .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(detail.tableName) · 第 \(detail.handNumber) 手")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(RCTheme.primaryText)
                Text("\(detail.localDay.rawValue) · 最终结果")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(RCTheme.secondaryText)
            }

            Spacer()

            Button("删除本局", systemImage: "trash", role: .destructive, action: onDelete)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("history.deleteOne")
        }
    }
}

private struct HandHistoryCommunityCards: View {
    let cards: [Card]

    var body: some View {
        HStack(spacing: 8) {
            Label("公共牌", systemImage: "rectangle.stack.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RCTheme.secondaryText)

            HStack(spacing: 5) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    TableCardView(card: card)
                        .frame(width: 34, height: 46)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RCTheme.surface, in: RoundedRectangle(cornerRadius: RCTheme.corner))
    }
}

private struct HandHistorySeatGrid: View {
    let seats: [HandHistorySeatResult]
    let layout: HandHistoryDetailLayout.Metrics

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: layout.columnSpacing),
                count: layout.columnCount
            ),
            spacing: layout.rowSpacing
        ) {
            ForEach(layout.seatSlots) { slot in
                if let seat = seats.first(where: { $0.id.rawValue == slot.id }) {
                    HandHistorySeatResultView(seat: seat, slot: slot)
                }
            }
        }
    }
}

private struct HandHistorySeatResultView: View {
    let seat: HandHistorySeatResult
    let slot: HandHistoryDetailLayout.SeatSlot

    var body: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(seat.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if seat.status == .winner {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(RCTheme.gold)
                    }
                }
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
                Text(deltaText)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(RCTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if seat.status == .notDealt {
                Text("未参与")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RCTheme.secondaryText)
                    .frame(minWidth: 65)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(seat.cards.prefix(2).enumerated()), id: \.offset) { index, card in
                        TableCardView(card: card)
                            .frame(
                                width: slot.cardSize.width,
                                height: slot.cardSize.height
                            )
                            .accessibilityIdentifier(
                                "history.holeCard.\(seat.id.rawValue).\(index)"
                            )
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: slot.frame.height)
        .background(
            seat.status == .winner ? RCTheme.surfaceRaised : RCTheme.surface,
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(
                    seat.status == .winner
                        ? RCTheme.gold.opacity(0.7)
                        : RCTheme.gold.opacity(0.12),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.seat.\(seat.id.rawValue)")
    }

    private var statusText: String {
        switch seat.status {
        case .winner: "赢家"
        case .folded: "已弃牌"
        case .showdown: "摊牌"
        case .notDealt: "未参与"
        }
    }

    private var statusColor: Color {
        switch seat.status {
        case .winner: RCTheme.gold
        case .folded: .orange
        case .showdown, .notDealt: RCTheme.secondaryText
        }
    }

    private var deltaText: String {
        if seat.chipDelta > 0 { return "+\(seat.chipDelta.formatted())" }
        if seat.chipDelta < 0 { return "−\((-seat.chipDelta).formatted())" }
        return "0"
    }
}

private struct HandHistoryPotList: View {
    let pots: [HandHistoryPotResult]
    let returns: [SeatID: Chips]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("底池分配", systemImage: "circle.grid.2x2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RCTheme.primaryText)

            ForEach(pots) { pot in
                HStack(spacing: 10) {
                    Text(pot.id == 0 ? "主池" : "边池 \(pot.id)")
                        .foregroundStyle(RCTheme.secondaryText)
                    Text(pot.amount.rawValue.formatted())
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(RCTheme.gold)
                    Spacer()
                    Text(winnerText(for: pot))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(RCTheme.primaryText)
                }
            }

            ForEach(returns.keys.sorted(), id: \.self) { seat in
                if let amount = returns[seat] {
                    HStack {
                        Text("座位 \(seat.rawValue + 1) 未跟注返还")
                            .foregroundStyle(RCTheme.secondaryText)
                        Spacer()
                        Text(amount.rawValue.formatted())
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundStyle(RCTheme.primaryText)
                    }
                }
            }
        }
        .padding(14)
        .background(RCTheme.surface, in: RoundedRectangle(cornerRadius: RCTheme.corner))
    }

    private func winnerText(for pot: HandHistoryPotResult) -> String {
        pot.amounts.keys.sorted().compactMap { seat in
            pot.amounts[seat].map {
                "座位 \(seat.rawValue + 1) +\($0.rawValue.formatted())"
            }
        }.joined(separator: " · ")
    }
}
