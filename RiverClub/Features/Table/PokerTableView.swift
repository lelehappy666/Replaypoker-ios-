import PokerCoordinator
import PokerCore
import SwiftUI

struct PokerTableView: View {
    @Bindable var coordinator: CashTableCoordinator
    let table: PokerTableSummary
    let balance: Int
    let onExit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSendingIntent = false
    @State private var animationPulse = false

    private var state: TableViewState { coordinator.state }

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

                ForEach(Array(state.seats.enumerated()), id: \.element.id) { index, seat in
                    if positions.indices.contains(index) {
                        ZStack {
                            PokerSeatView(
                                seat: seat,
                                secondsRemaining: seat.isCurrentActor
                                    ? state.secondsRemaining
                                    : nil,
                                isWinner: state.winners.contains(seat.id),
                                animationPulse: animationPulse,
                                reduceMotion: reduceMotion,
                                animation: state.animation
                            )

                            Color.clear
                                .contentShape(Rectangle())
                                .accessibilityElement()
                                .accessibilityLabel("第 \(index + 1) 个座位")
                                .accessibilityIdentifier("table.seat.\(index)")
                                .allowsHitTesting(false)
                        }
                        .position(x: positions[index].x, y: positions[index].y)
                    }
                }

                topBar
                    .accessibilityIdentifier("table.topBar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                chatControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                phaseControls
                    .frame(
                        width: PokerTableLayout.betControlSize.width,
                        height: PokerTableLayout.betControlSize.height,
                        alignment: .bottomTrailing
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .safeAreaPadding(.horizontal, 16)
        .safeAreaPadding(.vertical, 6)
        .background(RCTheme.background.ignoresSafeArea())
        .onChange(of: state.animation) { _, animation in
            guard animation != nil else { return }
            withAnimation(
                reduceMotion ? nil : .easeOut(duration: 0.22)
            ) {
                animationPulse.toggle()
            }
        }
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
            .shadow(color: .black.opacity(0.5), radius: reduceMotion ? 0 : 18, y: reduceMotion ? 0 : 8)
            .padding(.horizontal, 70)
            .padding(.vertical, 34)
            .accessibilityHidden(true)
    }

    private var centerBoard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(Array(state.communityCards.enumerated()), id: \.offset) { _, card in
                    TableCardView(card: card)
                        .frame(width: 34, height: 46)
                        .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                }
            }
            .scaleEffect(boardScale)

            Text("底池 \(state.pot.rawValue.formatted())")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(RCTheme.primaryText)
                .accessibilityIdentifier("table.pot")

            HStack(spacing: -5) {
                ForEach(0..<chipCount, id: \.self) { _ in
                    Circle()
                        .fill(RCTheme.gold)
                        .frame(width: 14, height: 14)
                        .overlay { Circle().stroke(RCTheme.background, lineWidth: 1) }
                }
            }
            .offset(y: potOffset)
            .accessibilityLabel("底池筹码堆")
        }
    }

    private var chipCount: Int {
        state.pot.rawValue == 0 ? 0 : min(6, max(1, state.pot.rawValue / 200))
    }

    private var boardScale: CGFloat {
        guard !reduceMotion,
              state.animation?.kind == .revealCommunityCard
        else { return 1 }
        return animationPulse ? 1 : 0.88
    }

    private var potOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        switch state.animation?.kind {
        case .moveCommitmentToPot:
            return animationPulse ? 7 : 0
        case .returnUncalledBet:
            return animationPulse ? -7 : 0
        case .awardPot:
            return animationPulse ? -12 : 0
        default:
            return 0
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

            ChipBalancePill(balance: balance)

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

    @ViewBuilder
    private var phaseControls: some View {
        switch state.phase {
        case .waitingForHuman:
            if let controls = state.controls {
                BetControlBar(
                    controls: controls,
                    pot: state.pot,
                    onIntent: send
                )
                .disabled(isSendingIntent)
            } else {
                statusPanel("等待操作")
            }
        case .awaitingNextHand:
            VStack(alignment: .trailing, spacing: 8) {
                statusText(PokerTablePresentation.status(for: state.phase))
                Button("下一手") { send(.nextHand) }
                    .buttonStyle(.borderedProminent)
                    .tint(RCTheme.gold)
                    .foregroundStyle(RCTheme.background)
                    .disabled(isSendingIntent)
                    .accessibilityIdentifier("action.nextHand")
            }
        case .saveFailed:
            TableErrorPanel(
                message: state.errorMessage ?? "牌局保存失败，请重试。",
                retryTitle: "重试保存",
                isRetrying: isSendingIntent,
                onRetry: { send(.retrySave) }
            )
        default:
            statusPanel(
                state.errorMessage ?? PokerTablePresentation.status(for: state.phase)
            )
        }
    }

    private func statusPanel(_ text: String) -> some View {
        statusText(text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.34), in: Capsule())
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(RCTheme.primaryText)
            .accessibilityIdentifier("table.phase")
    }

    private func send(_ intent: TableIntent) {
        guard !isSendingIntent else { return }
        isSendingIntent = true
        Task { @MainActor in
            defer { isSendingIntent = false }
            try? await coordinator.send(intent)
        }
    }
}

enum PokerTablePresentation {
    static func title(for table: PokerTableSummary) -> String {
        "\(table.name) · \(table.smallBlind.formatted()) / \(table.bigBlind.formatted())"
    }

    static func status(for phase: TableFlowPhase) -> String {
        switch phase {
        case .preparingHand: "正在准备牌局"
        case .dealing: "发牌中"
        case .waitingForHuman: "等待操作"
        case .botThinking: "思考中"
        case .animatingAction: "结算行动中"
        case .revealingBoard: "翻开公共牌"
        case .settling: "正在结算"
        case .savingResult: "正在保存结果"
        case .awaitingNextHand: "本手牌已结束"
        case .saveFailed: "牌局保存失败"
        case .suspended: "牌局已暂停"
        }
    }
}
