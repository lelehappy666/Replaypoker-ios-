import SwiftUI

struct PokerTableView: View {
    let table: PokerTableSummary
    let seats: [PokerSeat]
    @Bindable var session: AppSession
    let onExit: () -> Void

    private var orderedSeats: [PokerSeat] {
        let opponents = seats.filter { !$0.isLocalPlayer }.prefix(8)
        let localPlayer = seats.filter(\.isLocalPlayer).prefix(1)
        return Array(opponents + localPlayer)
    }

    var body: some View {
        GeometryReader { proxy in
            let positions = PokerTableLayout.positions(for: proxy.size)

            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityLabel("牌桌安全画布")
                    .accessibilityIdentifier("table.safeCanvas")

                tableSurface

                centerBoard
                    .frame(
                        width: PokerTableLayout.centerBoardRegion(for: proxy.size).width,
                        height: PokerTableLayout.centerBoardRegion(for: proxy.size).height
                    )
                    .position(
                        x: PokerTableLayout.centerBoardRegion(for: proxy.size).midX,
                        y: PokerTableLayout.centerBoardRegion(for: proxy.size).midY
                    )
                    .accessibilityIdentifier("table.centerBoard")

                ForEach(Array(orderedSeats.enumerated()), id: \.element.id) { index, seat in
                    PokerSeatView(seat: seat, isActing: index == 0)
                        .position(
                            x: positions[index].x,
                            y: positions[index].y
                        )
                        .accessibilityIdentifier("table.seat.\(index)")
                }

                topBar
                    .accessibilityIdentifier("table.topBar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                chatControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                BetControlBar(callAmount: 800, onFold: {}, onCall: {}, onRaise: { _ in })
                    .frame(
                        width: PokerTableLayout.betControlSize.width,
                        height: PokerTableLayout.betControlSize.height,
                        alignment: .bottomTrailing
                    )
                    .accessibilityIdentifier("table.betControls")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .safeAreaPadding(.horizontal, 16)
        .safeAreaPadding(.vertical, 6)
        .background(RCTheme.background.ignoresSafeArea())
    }

    private var tableSurface: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.06, green: 0.30, blue: 0.21), RCTheme.surface],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay { Capsule().stroke(Color(red: 0.30, green: 0.16, blue: 0.08), lineWidth: 12) }
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
            .padding(.horizontal, 70)
            .padding(.vertical, 34)
            .accessibilityHidden(true)
    }

    private var centerBoard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                CommunityCard(rank: "A", suit: "♠")
                CommunityCard(rank: "10", suit: "♥")
                CommunityCard(rank: "7", suit: "♦")
                CommunityCard(rank: "3", suit: "♣")
                CommunityCard(rank: "K", suit: "♠")
            }

            Text("底池 3,600")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(RCTheme.primaryText)
                .accessibilityIdentifier("table.pot")

            HStack(spacing: -5) {
                ForEach(0..<4, id: \.self) { _ in
                    Circle()
                        .fill(RCTheme.gold)
                        .frame(width: 14, height: 14)
                        .overlay { Circle().stroke(RCTheme.background, lineWidth: 1) }
                }
            }
            .accessibilityLabel("底池筹码堆")
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onExit) {
                Label("返回", systemImage: "chevron.left")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(RCTheme.gold)

            Text(PokerTablePresentation.title(for: table))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RCTheme.primaryText)

            Spacer()
            ChipBalancePill(balance: session.chipBalance)
            Button("设置", systemImage: "gearshape") {}
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .foregroundStyle(RCTheme.primaryText)
                .accessibilityLabel("牌桌设置")
        }
    }

    private var chatControls: some View {
        HStack(spacing: 8) {
            Button("聊天", systemImage: "bubble.left.fill") {}
            Button("表情", systemImage: "face.smiling") {}
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .tint(RCTheme.gold)
        .controlSize(.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("牌桌聊天和表情")
    }
}

private struct CommunityCard: View {
    let rank: String
    let suit: String

    var body: some View {
        VStack(spacing: -2) {
            Text(rank)
            Text(suit)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(suit == "♥" || suit == "♦" ? .red : .black)
        .frame(width: 34, height: 46)
        .background(.white, in: RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel("\(rank)\(suit)")
    }
}
