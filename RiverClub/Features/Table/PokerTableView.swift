import PokerCoordinator
import PokerCore
import SwiftUI

struct PokerTableView: View {
    @Bindable var coordinator: CashTableCoordinator
    let table: PokerTableSummary
    let balance: Int
    let sendIntent: @MainActor (TableIntent) async throws -> Void
    var onRequestLeave: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var actionRequest = TableActionRequestModel()
    @State private var animationPresentation = TableAnimationPresentation()
    @State private var animationResetTask: Task<Void, Never>?
    @State private var actionTask: Task<Void, Never>?
    @State private var retryTask: Task<Void, Never>?

    private var state: TableViewState { coordinator.state }

    var body: some View {
        GeometryReader { proxy in
            let positions = PokerTableLayout.positions(for: proxy.size)

            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityLabel("牌桌安全画布")
                    .accessibilityValue(state.handID ?? "尚未开局")
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
                                reduceMotion: reduceMotion,
                                animation: animationPresentation
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
        .onChange(of: state.animationSequence) { _, sequence in
            present(state.animation, sequence: sequence)
        }
        .onDisappear {
            cancelViewTasks()
        }
        .onChange(of: state.phase) { _, phase in
            if phase == .suspended {
                actionTask?.cancel()
                retryTask?.cancel()
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
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                ForEach(Array(state.communityCards.enumerated()), id: \.offset) { index, card in
                    TableCardView(card: card)
                        .frame(
                            width: PokerTableLayout.communityCardSize.width,
                            height: PokerTableLayout.communityCardSize.height
                        )
                        .scaleEffect(
                            reduceMotion ? 1 : animationPresentation.communityCardScale(at: index)
                        )
                        .opacity(
                            reduceMotion ? 1 : animationPresentation.communityCardOpacity(at: index)
                        )
                }
            }

            if let currentHandText {
                Text(currentHandText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(RCTheme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .accessibilityIdentifier("table.currentHand")
            }

            Text("底池 \(state.pot.rawValue.formatted())")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(RCTheme.primaryText)
                .accessibilityIdentifier("table.pot")

            HStack(spacing: -5) {
                ForEach(0..<chipCount, id: \.self) { _ in
                    Circle()
                        .fill(RCTheme.gold)
                        .frame(width: 10, height: 10)
                        .overlay { Circle().stroke(RCTheme.background, lineWidth: 1) }
                }
            }
            .offset(y: reduceMotion ? 0 : animationPresentation.chipOffset)
            .accessibilityLabel("底池筹码堆")
        }
    }

    private var chipCount: Int {
        state.pot.rawValue == 0 ? 0 : min(6, max(1, state.pot.rawValue / 200))
    }

    private var currentHandText: String? {
        guard let human = state.seats.first(where: \.isHuman) else {
            return nil
        }
        let holeCards = human.cards.compactMap { cardState -> Card? in
            guard case let .faceUp(card) = cardState else { return nil }
            return card
        }
        return CurrentHandPresentation.text(
            holeCards: holeCards,
            communityCards: state.communityCards
        )
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                onRequestLeave()
            } label: {
                Label("离桌", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .tint(RCTheme.gold)
            .frame(minHeight: 44)
            .accessibilityIdentifier("table.leave")

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
        ZStack(alignment: .bottomTrailing) {
            phaseContent

            if let errorMessage = actionRequest.errorMessage {
                localErrorPanel(message: errorMessage)
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .waitingForHuman:
            if let controls = state.controls {
                BetControlBar(controls: controls, pot: state.pot, onIntent: send)
                    .disabled(actionRequest.isSending)
            } else { statusPanel("等待操作") }
        case .awaitingNextHand:
            VStack(alignment: .trailing, spacing: 8) {
                statusText(PokerTablePresentation.status(for: state.phase))
                Button("下一手") { send(.nextHand) }
                    .buttonStyle(.borderedProminent)
                    .tint(RCTheme.gold)
                    .foregroundStyle(RCTheme.background)
                    .disabled(actionRequest.isSending)
                    .accessibilityIdentifier("action.nextHand")
            }
        case .saveFailed:
            TableErrorPanel(
                message: state.errorMessage ?? "牌局保存失败，请重试。",
                retryTitle: "重试保存",
                isRetrying: actionRequest.isSending,
                onRetry: { send(.retrySave) }
            )
        default:
            statusPanel(state.errorMessage ?? PokerTablePresentation.status(for: state.phase))
        }
    }

    private func localErrorPanel(message: String) -> some View {
        VStack(spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            HStack {
                Button("关闭") { actionRequest.dismissError() }
                    .accessibilityIdentifier("action.dismissError")
                if actionRequest.canRetry(for: state.phase) {
                    Button("重试") {
                        retryFailedAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("action.retryIntent")
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table.actionError")
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
        actionTask = Task { @MainActor in
            await actionRequest.send(intent) { intent in
                try await sendIntent(intent)
            }
        }
    }

    private func retryFailedAction() {
        retryTask = Task { @MainActor in
            await actionRequest.retry(
                for: state.phase,
                send: sendIntent,
                resume: { try await coordinator.resume() }
            )
        }
    }

    private func cancelViewTasks() {
        actionTask?.cancel()
        retryTask?.cancel()
        animationResetTask?.cancel()
        actionTask = nil
        retryTask = nil
        animationResetTask = nil
    }

    private func present(_ event: TableAnimationEvent?, sequence: Int) {
        animationResetTask?.cancel()

        guard let event, !reduceMotion else {
            animationPresentation = TableAnimationPresentation()
            return
        }

        animationPresentation.begin(event, token: sequence)
        withAnimation(.easeOut(duration: 0.22)) {
            animationPresentation.advance(token: sequence)
        }
        animationResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                animationPresentation.reset(token: sequence)
            }
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
