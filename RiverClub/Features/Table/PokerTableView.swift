import Foundation
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
    @State private var uiTestingWinnerAnnouncements: [String] = []

    private var state: TableViewState { coordinator.state }

    var body: some View {
        GeometryReader { proxy in
            let reference = PokerTableLayout.referenceCanvas
            let scale = PokerTableLayout.referenceScale(for: proxy.size)

            tableCanvas(canvas: reference)
                .frame(width: reference.width, height: reference.height)
                .scaleEffect(scale)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .ignoresSafeArea()
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.075, blue: 0.072),
                    RCTheme.background,
                    Color.black,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .onChange(of: state.animationSequence) { _, sequence in
            present(state.animation, sequence: sequence)
        }
        #if DEBUG
        .task { await startUITestingPayoutScenarioIfNeeded() }
        #endif
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

    private func tableCanvas(canvas: CGSize) -> some View {
        let positions = PokerTableLayout.positions(for: canvas)
        let seatFrameSize = PokerTableLayout.seatFrameSize(for: canvas)
        let betFrames = PokerTableLayout.betFrames(for: canvas)
        let surface = PokerTableLayout.tableSurfaceFrame(for: canvas)
        let action = PokerTableLayout.betControlRegion(for: canvas)

        return ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityLabel("牌桌安全画布")
                    .accessibilityValue(state.handID ?? "尚未开局")
                    .accessibilityIdentifier("table.safeCanvas")

                tableSurface
                    .frame(width: surface.width, height: surface.height)
                    .position(x: surface.midX, y: surface.midY)

                centerBoard(canvas: canvas)
                    .frame(
                        width: PokerTableLayout.centerBoardRegion(for: canvas).width,
                        height: PokerTableLayout.centerBoardRegion(for: canvas).height
                    )
                    .position(
                        x: PokerTableLayout.centerBoardRegion(for: canvas).midX,
                        y: PokerTableLayout.centerBoardRegion(for: canvas).midY
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("table.centerBoard")

                awardAnimationLayer(canvas: canvas)

                if uiTestingWinnerAnnouncementLogEnabled {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .opacity(0.001)
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel("测试派彩公告记录")
                        .accessibilityValue(uiTestingWinnerAnnouncements.joined(separator: ","))
                        .accessibilityIdentifier("table.uiTestingPayoutLog")
                }

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
                        }
                        .frame(
                            width: PokerTableLayout.seatSize.width,
                            height: PokerTableLayout.seatSize.height
                        )
                        .scaleEffect(seatFrameSize.width / PokerTableLayout.seatSize.width)
                        .frame(width: seatFrameSize.width, height: seatFrameSize.height)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("第 \(index + 1) 个座位")
                        .accessibilityIdentifier("table.seat.\(index)")
                        .position(x: positions[index].x, y: positions[index].y)
                    }
                }

                ForEach(Array(state.seats.enumerated()), id: \.element.id) { index, seat in
                    if positions.indices.contains(index),
                       seat.committedThisStreet.rawValue > 0,
                       betFrames.indices.contains(index),
                       let betFrame = betFrames[index] {
                        ZStack {
                            CasinoChipPileView(
                                amount: seat.committedThisStreet.rawValue,
                                scale: PokerTableLayout.betScale(for: canvas),
                                stackCount: seat.committedThisStreet.rawValue >= 500 ? 2 : 1
                            )
                        }
                        .frame(width: betFrame.width, height: betFrame.height)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("table.bet.\(index)")
                        .position(x: betFrame.midX, y: betFrame.midY)
                    }
                }

                topBar
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("table.topBar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 30)
                    .padding(.top, 10)

                chatControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 28)
                    .padding(.bottom, 18)

                phaseControls
                    .frame(
                        width: action.width,
                        height: action.height,
                        alignment: .bottomTrailing
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("table.betControls")
                    .position(x: action.midX, y: action.midY)
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
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.48, green: 0.27, blue: 0.12),
                                Color(red: 0.20, green: 0.10, blue: 0.05),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 12
                    )
            }
            .shadow(color: .black.opacity(0.5), radius: reduceMotion ? 0 : 18, y: reduceMotion ? 0 : 8)
            .accessibilityHidden(true)
    }

    private func centerBoard(canvas: CGSize) -> some View {
        let board = PokerTableLayout.centerBoardRegion(for: canvas)
        let currentHandFrame = PokerTableLayout.currentHandFrame(for: canvas)
        let potFrame = PokerTableLayout.potFrame(for: canvas)

        return GeometryReader { proxy in
            if let currentHandText {
                Text(currentHandText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(RCTheme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .accessibilityIdentifier("table.currentHand")
                    .frame(width: currentHandFrame.width, height: currentHandFrame.height)
                    .position(
                        x: currentHandFrame.midX - board.minX,
                        y: currentHandFrame.midY - board.minY
                    )
            }

            HStack(spacing: PokerTableLayout.holeCardSpacing) {
                ForEach(0..<5, id: \.self) { index in
                    Group {
                        if state.communityCards.indices.contains(index) {
                            TableCardView(card: state.communityCards[index])
                                .scaleEffect(
                                    reduceMotion ? 1 : animationPresentation.communityCardScale(at: index)
                                )
                                .opacity(
                                    reduceMotion ? 1 : animationPresentation.communityCardOpacity(at: index)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    RCTheme.gold.opacity(0.24),
                                    style: StrokeStyle(lineWidth: 1, dash: [4])
                                )
                                .accessibilityLabel("未发公共牌槽")
                        }
                    }
                    .frame(
                        width: PokerTableLayout.communityCardSize.width,
                        height: PokerTableLayout.communityCardSize.height
                    )
                    .accessibilityIdentifier("table.communitySlot.\(index)")
                }
            }
            .position(
                x: proxy.size.width / 2,
                y: PokerTableLayout.communityCardFrames(for: canvas)[0].midY - board.minY
            )

            VStack(spacing: 1) {
                Text("底池 \(CasinoChipAmountPresentation.text(for: state.pot.rawValue))")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(RCTheme.primaryText)
                CasinoChipPileView(
                    amount: state.pot.rawValue,
                    scale: 0.82,
                    showsAmount: false,
                    stackCount: 5
                )
                .frame(width: 92, height: 42)
            }
            .frame(width: potFrame.width, height: potFrame.height)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("table.pot")
            .position(
                x: potFrame.midX - board.minX,
                y: potFrame.midY - board.minY
            )
        }
    }

    @ViewBuilder
    private func awardAnimationLayer(canvas: CGSize) -> some View {
        if let targetSeat = animationPresentation.awardTargetSeat,
           let amount = animationPresentation.awardAmount,
           let seatIndex = state.seats.firstIndex(where: { $0.id == targetSeat }),
           let payoutPosition = PokerTableLayout.payoutPosition(
               toSeatAt: seatIndex,
               canvas: canvas,
               progress: reduceMotion ? 1 : animationPresentation.awardProgress
           ) {
            let center = PokerTableLayout.centerBoardRegion(for: canvas)

            CasinoChipStackView(
                amount: amount.rawValue,
                scale: 1,
                maximumVisibleChips: 3
            )
            .frame(width: 68, height: 44)
            .position(x: payoutPosition.x, y: payoutPosition.y)
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("table.awardChips")

            Text("\(displayName(for: targetSeat)) 赢得 \(amount.rawValue.formatted())")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RCTheme.gold)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.72), in: Capsule())
                .position(x: center.midX, y: max(72, center.minY - 12))
                .accessibilityIdentifier("table.winnerAnnouncement")
        }
    }

    private func displayName(for seat: SeatID) -> String {
        state.seats.first(where: { $0.id == seat })?.displayName ?? "玩家"
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

            HStack(spacing: 5) {
                CasinoChipPileView(
                    amount: balance,
                    scale: 0.72,
                    showsAmount: false,
                    stackCount: 4
                )
                .frame(width: 70, height: 36)
                Text(CasinoChipAmountPresentation.text(for: balance))
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(RCTheme.gold)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 42)
            .background(RCTheme.surface.opacity(0.82), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("table.balance")

            Button("设置", systemImage: "gearshape") {}
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .foregroundStyle(RCTheme.primaryText)
                .accessibilityLabel("牌桌设置")
        }
    }

    private var chatControls: some View {
        VStack(spacing: 4) {
            Button("聊天", systemImage: "bubble.left.fill") {}
            Button("表情", systemImage: "face.smiling") {}
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .tint(RCTheme.gold)
        .controlSize(.regular)
        .frame(width: 40)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("牌桌聊天和表情")
    }

    @ViewBuilder
    private var phaseControls: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let errorMessage = actionRequest.errorMessage {
                localErrorPanel(message: errorMessage)
            }

            Spacer(minLength: 0)
            phaseContent
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
        HStack(spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)
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
        .padding(10)
        .frame(maxWidth: PokerTableLayout.betControlSize.width)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: RCTheme.corner)
                .stroke(.orange.opacity(0.35), lineWidth: 1)
        }
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

        guard let event else {
            animationPresentation = TableAnimationPresentation()
            return
        }

        animationPresentation.begin(event, token: sequence)
        if uiTestingWinnerAnnouncementLogEnabled,
           case let .awardPot(seat, amount) = event {
            uiTestingWinnerAnnouncements.append(
                "\(seat.rawValue)|\(displayName(for: seat))|\(amount.rawValue)"
            )
        }
        if reduceMotion {
            animationPresentation.advance(token: sequence)
            animationResetTask = Task { @MainActor in
                try? await Task.sleep(
                    for: .milliseconds(event.kind == .awardPot ? 560 : 220)
                )
                guard !Task.isCancelled else { return }
                animationPresentation.reset(token: sequence)
            }
            return
        }
        let duration = event.kind == .awardPot ? 0.52 : 0.22
        withAnimation(.easeInOut(duration: duration)) {
            animationPresentation.advance(token: sequence)
        }
        animationResetTask = Task { @MainActor in
            try? await Task.sleep(
                for: .milliseconds(event.kind == .awardPot ? 560 : 220)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                animationPresentation.reset(token: sequence)
            }
        }
    }

    private var uiTestingWinnerAnnouncementLogEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        return arguments.contains("-uiTesting")
            && arguments.contains("-uiTestingPayoutLog")
            && arguments.contains("-uiTestingPayoutScenario")
        #else
        return false
        #endif
    }

    #if DEBUG
    private func startUITestingPayoutScenarioIfNeeded() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uiTesting"),
              let flag = arguments.firstIndex(of: "-uiTestingPayoutScenario"),
              arguments.indices.contains(flag + 1)
        else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        do {
            let seat2 = try SeatID(2)
            let seat4 = try SeatID(4)
            let seat8 = try SeatID(8)
            let events: [PublicGameEvent]
            switch arguments[flag + 1] {
            case "single":
                events = [.potAwarded(potIndex: 0, winners: [seat4], amounts: [seat4: try Chips(800)])]
            case "split":
                events = [
                    .potAwarded(potIndex: 0, winners: [seat8, seat2], amounts: [seat8: try Chips(500), seat2: try Chips(250)]),
                    .potAwarded(potIndex: 1, winners: [seat8], amounts: [seat8: try Chips(0)]),
                ]
            default: return
            }
            try await coordinator.presentUITestingPayout(events: events)
        } catch { return }
    }
    #endif
}

enum PokerTablePresentation {
    static func title(for table: PokerTableSummary) -> String {
        "\(table.name) · \(blinds(small: table.smallBlind, big: table.bigBlind))"
    }

    static func blinds(small: Int, big: Int) -> String {
        "\(small.formatted()) / \(big.formatted())"
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
