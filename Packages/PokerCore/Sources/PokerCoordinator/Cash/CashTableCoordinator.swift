import Observation
import Foundation
import PokerBot
import PokerCore
import PokerSession

@MainActor @Observable
public final class CashTableCoordinator {
    public private(set) var state: TableViewState
    package private(set) var frozenSettings: BotSettings?

    private let store: LocalPokerStore
    private let humanSeat: SeatID
    private let seatProfiles: [TableSeatProfile]
    private let dependencies: TableRuntimeDependencies
    private let botService: any BotDecisionServing
    private var currentHandID: HandID?
    private var pendingSettlementID: BusinessID?
    private var settlementPipelineRunning = false
    private var winnerSeats: Set<SeatID> = []
    package private(set) var completeWinnerSeats: Set<SeatID> = []
    private var stateVersion = 0
    private var animationSequence = 0
    private nonisolated let countdownTask = CountdownTaskBox()
    private nonisolated let botTask = BotTaskBox()
    private var botCancellationTask: Task<Void, Never>?
    private var botCancellationGeneration: UInt = 0

    @discardableResult
    public static func validateSeatProfiles(
        _ profiles: [TableSeatProfile],
        matching seats: [SeatID],
        humanSeat: SeatID
    ) throws -> [SeatID: TableSeatProfile] {
        try CashTableProjection.validatedProfiles(
            profiles,
            matching: seats,
            humanSeat: humanSeat
        )
    }

    public convenience init(
        store: LocalPokerStore,
        humanSeat: SeatID,
        seatProfiles: [TableSeatProfile],
        dependencies: TableRuntimeDependencies
    ) throws {
        try self.init(
            store: store,
            humanSeat: humanSeat,
            seatProfiles: seatProfiles,
            dependencies: dependencies,
            botService: BotDecisionService()
        )
    }

    package init(
        store: LocalPokerStore,
        humanSeat: SeatID,
        seatProfiles: [TableSeatProfile],
        dependencies: TableRuntimeDependencies,
        botService: any BotDecisionServing
    ) throws {
        guard let session = store.cashSession else {
            throw PokerCoordinatorError.missingObservation
        }
        let profileBySeat = try Self.validateSeatProfiles(
            seatProfiles,
            matching: session.seats.map(\.id),
            humanSeat: humanSeat
        )
        guard session.humanSeat == humanSeat else {
            throw PokerCoordinatorError.missingObservation
        }

        let initialSeats = try session.seats.sorted { $0.id < $1.id }.map { seat in
            guard let profile = profileBySeat[seat.id] else {
                throw PokerCoordinatorError.missingObservation
            }
            return TableSeatState(
                id: seat.id,
                displayName: profile.displayName,
                isHuman: seat.id == humanSeat,
                stack: seat.stack,
                committedThisStreet: try Chips(0),
                hasFolded: seat.hasFolded,
                isAllIn: seat.isAllIn,
                isDealer: seat.id == session.dealer,
                isCurrentActor: false,
                cards: []
            )
        }
        let initialState = TableViewState(
            handID: nil,
            stateVersion: 0,
            animationSequence: 0,
            phase: .awaitingNextHand,
            seats: initialSeats,
            communityCards: [],
            pot: try Chips(0),
            controls: nil,
            secondsRemaining: nil,
            winners: [],
            errorMessage: nil,
            animation: nil
        )

        self.store = store
        self.humanSeat = humanSeat
        self.seatProfiles = seatProfiles
        self.dependencies = dependencies
        self.botService = botService
        state = initialState
    }

    deinit {
        countdownTask.cancel()
        botTask.cancel()
    }

    public func startHand(settings: BotSettings) async throws {
        guard store.cashSession?.phase == .readyForHand else {
            throw PokerCoordinatorError.invalidPhase
        }
        frozenSettings = settings
        pendingSettlementID = nil
        winnerSeats = []
        completeWinnerSeats = []
        try refillBustedBotsToOneHundredBigBlinds()

        let beforeSnapshot = transitionSnapshot()
        let handID = try dependencies.nextHandID()
        let transition = try store.startHand(
            id: handID,
            seed: dependencies.nextSeed()
        )
        currentHandID = handID
        do {
            incrementStateVersion()
            let operationVersion = stateVersion
            guard try await present(
                transition,
                beforeAction: beforeSnapshot,
                guardedBy: operationVersion
            ) else { return }
            guard isCurrentOperation(operationVersion) else { return }
            try refreshProjection()
            guard isCurrentOperation(operationVersion) else { return }
            await scheduleCurrentActorIfReady()
        } catch {
            suspend()
            throw error
        }
    }

    public func resume() async throws {
        guard state.phase == .suspended else {
            throw PokerCoordinatorError.invalidPhase
        }
        cancelCountdown()
        await finishPendingBotCancellation()
        guard let phase = store.cashSession?.phase else {
            throw PokerCoordinatorError.invalidPhase
        }

        switch phase {
        case .readyForHand:
            throw PokerCoordinatorError.invalidPhase
        case .handInProgress, .settlementPending:
            guard currentHandID != nil else {
                throw PokerCoordinatorError.invalidPhase
            }
            do {
                incrementStateVersion()
                try refreshProjection()
                var operationVersion = stateVersion
                guard try await advanceCompletedRounds(
                    operationVersion: &operationVersion
                ) else { return }
                await scheduleCurrentActorIfReady()
            } catch {
                suspend()
                throw error
            }
        case .left:
            throw PokerCoordinatorError.invalidPhase
        }
    }

    public func send(_ intent: TableIntent) async throws {
        guard state.phase != .suspended else {
            throw PokerCoordinatorError.suspended
        }
        switch intent {
        case .nextHand:
            throw PokerCoordinatorError.invalidPhase
        case .retrySave:
            try await retrySave()
            return
        case .fold, .middle, .aggressive:
            break
        }
        guard let observation = try store.humanObservation(),
              observation.currentActor == humanSeat,
              let legalActions = observation.legalActions
        else {
            throw PokerCoordinatorError.illegalIntent
        }
        let action = try CashTableActionPipeline.action(
            for: intent,
            legalActions: legalActions
        )
        try await applyHumanAction(action)
    }

    public func startNextHand(settings: BotSettings) async throws {
        guard state.phase == .awaitingNextHand else {
            throw PokerCoordinatorError.invalidPhase
        }
        try await startHand(settings: settings)
    }

    public func retrySave() async throws {
        guard state.phase == .saveFailed,
              pendingSettlementID != nil
        else {
            throw PokerCoordinatorError.invalidPhase
        }
        await finishSettlement()
    }

    package func finishSettlement() async {
        guard state.phase != .suspended,
              !settlementPipelineRunning,
              store.cashSession?.phase == .settlementPending,
              currentHandID != nil
        else { return }

        if pendingSettlementID == nil {
            do {
                pendingSettlementID = try dependencies.nextBusinessID("settlement")
            } catch {
                state = stateReplacing(
                    phase: .settling,
                    errorMessage: "无法创建牌局保存编号。"
                )
                return
            }
        }
        guard let transactionID = pendingSettlementID else { return }

        settlementPipelineRunning = true
        defer { settlementPipelineRunning = false }
        guard let showdown = store.pendingShowdownObservation else {
            state = stateReplacing(
                phase: .saveFailed,
                errorMessage: "牌局保存失败，请重试。"
            )
            return
        }

        cancelCountdown()
        cancelBotDecision()
        incrementStateVersion()
        do {
            try refreshProjection()
        } catch {
            state = stateReplacing(
                phase: .saveFailed,
                errorMessage: "牌局保存失败，请重试。"
            )
            return
        }
        let revealedSeats = state.seats.map { seat in
            TableSeatState(
                id: seat.id,
                displayName: seat.displayName,
                isHuman: seat.isHuman,
                stack: seat.stack,
                committedThisStreet: seat.committedThisStreet,
                hasFolded: seat.hasFolded,
                isAllIn: seat.isAllIn,
                isDealer: seat.isDealer,
                isCurrentActor: false,
                cards: showdown.cardsBySeat[seat.id]
                    .map { $0.map(TableCardState.faceUp) }
                    ?? [.faceDown, .faceDown]
            )
        }
        state = TableViewState(
            handID: state.handID,
            stateVersion: stateVersion,
            animationSequence: animationSequence,
            phase: .settling,
            seats: revealedSeats,
            communityCards: state.communityCards,
            pot: state.pot,
            controls: nil,
            secondsRemaining: nil,
            winners: completeWinnerSeats,
            errorMessage: nil,
            animation: state.animation
        )
        do {
            state = stateReplacing(phase: .savingResult, errorMessage: nil)
            _ = try store.commitPendingHand(transactionID: transactionID)
            applyCommittedSettlementState()
        } catch {
            state = stateReplacing(
                phase: .saveFailed,
                errorMessage: "牌局保存失败，请重试。"
            )
        }
    }

    public func suspend() {
        guard (store.cashSession?.phase == .handInProgress
                || store.cashSession?.phase == .settlementPending),
              state.phase != .suspended,
              state.phase != .saveFailed,
              state.phase != .awaitingNextHand
        else { return }
        cancelCountdown()
        cancelBotDecision()
        incrementStateVersion()
        state = replacingState(phase: .suspended, secondsRemaining: nil)
    }

    package func runUntilHumanOrSettlement() async throws {
        while store.cashSession?.phase == .handInProgress,
              store.cashSession?.currentActor != humanSeat,
              state.phase != .suspended,
              state.errorMessage == nil {
            await Task.yield()
        }
    }

    private func refillBustedBotsToOneHundredBigBlinds() throws {
        guard let config = store.activeCashConfig,
              let session = store.cashSession
        else {
            throw PokerCoordinatorError.chipArithmeticOverflow
        }
        let target = try Self.oneHundredBigBlindBotTarget(for: config.bigBlind)

        for seat in session.seats where seat.id != humanSeat && seat.stack.rawValue == 0 {
            try store.refillBotSeat(seat.id, to: target)
        }
    }

    private func incrementStateVersion() {
        let (next, overflow) = stateVersion.addingReportingOverflow(1)
        stateVersion = overflow ? Int.max : next
    }

    private func refreshProjection(
        animation: TableAnimationEvent? = nil,
        secondsRemaining: Int? = nil
    ) throws {
        guard let currentHandID else {
            throw PokerCoordinatorError.missingObservation
        }
        let publishedSequence: Int
        if animation != nil {
            let (next, overflow) = animationSequence.addingReportingOverflow(1)
            guard !overflow else {
                throw PokerCoordinatorError.animationSequenceOverflow
            }
            publishedSequence = next
        } else {
            publishedSequence = animationSequence
        }
        let projection = try CashTableProjection.make(
            store: store,
            handID: currentHandID,
            stateVersion: stateVersion,
            animationSequence: publishedSequence,
            humanSeat: humanSeat,
            seatProfiles: seatProfiles,
            animation: animation,
            secondsRemaining: secondsRemaining
        )
        state = projection
        animationSequence = publishedSequence
    }

    private func scheduleCurrentActorIfReady() async {
        cancelCountdown()
        guard state.phase != .suspended else { return }
        if store.cashSession?.phase == .settlementPending {
            await finishSettlement()
            return
        }
        guard let handID = currentHandID,
              store.cashSession?.phase == .handInProgress,
              let actor = store.cashSession?.currentActor
        else { return }

        if actor != humanSeat {
            scheduleBotDecision(for: actor, handID: handID)
            return
        }

        let version = stateVersion
        do {
            try refreshProjection(secondsRemaining: 30)
        } catch {
            return
        }
        let sleep = dependencies.sleep
        let task = Task { @MainActor [weak self, sleep] in
            for remaining in stride(from: 29, through: 0, by: -1) {
                do {
                    try await sleep(.seconds(1))
                    try Task.checkCancellation()
                } catch {
                    return
                }
                guard let self else { return }
                await self.receiveCountdownTick(
                    remaining: remaining,
                    handID: handID,
                    stateVersion: version
                )
                guard remaining > 0,
                      self.currentHandID == handID,
                      self.stateVersion == version
                else { return }
            }
        }
        countdownTask.replace(with: task)
    }

    private func scheduleBotDecision(for actor: SeatID, handID: HandID) {
        guard let session = store.cashSession,
              let config = store.activeCashConfig,
              let settings = frozenSettings,
              session.phase == .handInProgress,
              session.currentActor == actor,
              actor != humanSeat
        else { return }

        let player: PlayerObservation
        do {
            player = try Self.requireBotPlayerObservation(
                store.playerObservation(for: actor)
            )
        } catch {
            showBotError()
            return
        }

        let version = stateVersion
        let observation: BotObservation
        do {
            observation = try BotObservation(
                handID: handID.rawValue,
                stateVersion: version,
                config: config,
                observation: player
            )
        } catch {
            showBotError()
            return
        }
        let request = BotDecisionRequest(
            observation: observation,
            settings: settings,
            stableIdentity: "cash:\(session.id.rawValue):seat:\(actor.rawValue)",
            seed: dependencies.nextSeed(),
            history: nil
        )
        let service = botService
        let task = Task { @MainActor [weak self, service] in
            let decision = await service.decide(request)
            guard !Task.isCancelled else { return }
            await self?.handleBotDecision(
                decision,
                actor: actor,
                handID: handID,
                stateVersion: version
            )
        }
        botTask.replace(with: task)
    }

    private func handleBotDecision(
        _ decision: BotDecision?,
        actor: SeatID,
        handID: HandID,
        stateVersion version: Int
    ) async {
        guard currentHandID == handID,
              stateVersion == version,
              state.phase != .suspended,
              store.cashSession?.phase == .handInProgress,
              store.cashSession?.currentActor == actor
        else { return }

        let action: PlayerAction?
        if let decision {
            guard decision.handID == handID.rawValue,
                  decision.stateVersion == version
            else {
                showBotError()
                return
            }
            action = decision.action
        } else {
            let latest = try? store.playerObservation(for: actor)
            action = latest?.legalActions.flatMap(
                CashTableActionPipeline.fallbackAction
            )
        }
        guard let action else {
            showBotError()
            return
        }

        do {
            try await applyBotAction(
                action,
                actor: actor,
                handID: handID,
                stateVersion: version
            )
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  currentHandID == handID,
                  state.phase != .suspended
            else { return }
            showBotError()
        }
    }

    private func applyBotAction(
        _ action: PlayerAction,
        actor: SeatID,
        handID: HandID,
        stateVersion version: Int
    ) async throws {
        guard currentHandID == handID,
              stateVersion == version,
              store.cashSession?.currentActor == actor
        else { return }
        let beforeSnapshot = transitionSnapshot()
        let transition = try store.apply(action, by: actor)
        incrementStateVersion()
        var operationVersion = stateVersion
        guard try await present(
            transition,
            beforeAction: beforeSnapshot,
            guardedBy: operationVersion
        ) else { return }
        guard isCurrentOperation(operationVersion) else { return }
        try refreshProjection()
        guard try await advanceCompletedRounds(
            operationVersion: &operationVersion
        ) else { return }
        guard isCurrentOperation(operationVersion) else { return }
        botTask.clear()
        await scheduleCurrentActorIfReady()
    }

    private func handleCountdownTick(
        remaining: Int,
        handID: HandID,
        stateVersion version: Int
    ) -> CountdownTickResult {
        guard currentHandID == handID,
              stateVersion == version,
              store.cashSession?.phase == .handInProgress,
              store.cashSession?.currentActor == humanSeat
        else {
            cancelCountdown()
            return .stop
        }
        if remaining > 0 {
            try? refreshProjection(secondsRemaining: remaining)
            return .continueCountdown
        }
        return .performTimeout
    }

    package func receiveCountdownTick(
        remaining: Int,
        handID: HandID,
        stateVersion version: Int
    ) async {
        switch handleCountdownTick(
            remaining: remaining,
            handID: handID,
            stateVersion: version
        ) {
        case .continueCountdown, .stop:
            return
        case .performTimeout:
            await performTimeout(handID: handID, stateVersion: version)
        }
    }

    private func performTimeout(handID: HandID, stateVersion version: Int) async {
        guard currentHandID == handID,
              stateVersion == version,
              let observation = try? store.humanObservation(),
              observation.currentActor == humanSeat,
              let legalActions = observation.legalActions
        else { return }

        let action: PlayerAction?
        if legalActions.canCheck {
            action = .check
        } else if legalActions.canFold {
            action = .fold
        } else {
            action = nil
        }
        guard let action else { return }
        countdownTask.clear()
        try? await applyHumanAction(action)
    }

    private func applyHumanAction(_ action: PlayerAction) async throws {
        let beforeSnapshot = transitionSnapshot()
        let transition = try store.apply(action, by: humanSeat)
        cancelCountdown()
        incrementStateVersion()
        var operationVersion = stateVersion
        guard try await present(
            transition,
            beforeAction: beforeSnapshot,
            guardedBy: operationVersion
        ) else { return }
        guard isCurrentOperation(operationVersion) else { return }
        try refreshProjection()
        guard try await advanceCompletedRounds(
            operationVersion: &operationVersion
        ) else { return }
        guard isCurrentOperation(operationVersion) else { return }
        await scheduleCurrentActorIfReady()
    }

    private func advanceCompletedRounds(
        operationVersion: inout Int
    ) async throws -> Bool {
        while store.cashSession?.phase == .handInProgress,
              store.cashSession?.currentActor == nil {
            guard isCurrentOperation(operationVersion) else { return false }
            let beforeSnapshot = transitionSnapshot()
            let transition = try store.advanceIfRoundComplete()
            incrementStateVersion()
            operationVersion = stateVersion
            guard try await present(
                transition,
                beforeAction: beforeSnapshot,
                guardedBy: operationVersion
            ) else { return false }
            guard isCurrentOperation(operationVersion) else { return false }
            try refreshProjection()
        }
        return true
    }

    private func present(
        _ transition: GameTransition,
        beforeAction: CashTableAnimationSnapshot,
        guardedBy operationVersion: Int
    ) async throws -> Bool {
        completeWinnerSeats.formUnion(
            CashTableAnimationMapper.completeWinnerSeats(in: transition.events)
        )
        let humanCards = try store.humanObservation()?.ownHoleCards
            .map(TableCardState.faceUp) ?? []
        let animations = try CashTableAnimationMapper.map(
            transition.events,
            humanSeat: humanSeat,
            humanCards: humanCards,
            beforeAction: beforeAction
        )
        var animationStreet: Street?
        let startsNewHand = transition.events.contains { event in
            if case .handStarted = event { return true }
            return false
        }
        var visibleCards: [SeatID: [TableCardState]] = startsNewHand
            ? [:]
            : Dictionary(uniqueKeysWithValues: state.seats.map { ($0.id, $0.cards) })
        var visibleCommunityCards: [Card] = startsNewHand
            ? []
            : state.communityCards
        for animation in animations {
            guard isCurrentOperation(operationVersion) else { return false }
            let publishedAnimation: TableAnimationEvent
            switch animation {
            case let .dealHoleCard(seat, card):
                visibleCards[seat, default: []].append(card)
                publishedAnimation = animation
            case let .revealCommunityCard(card, _):
                publishedAnimation = .revealCommunityCard(
                    card: card,
                    index: visibleCommunityCards.count
                )
                visibleCommunityCards.append(card)
            default:
                publishedAnimation = animation
            }
            if case let .highlightWinner(seat) = animation {
                winnerSeats.insert(seat)
            }
            if case let .streetChanged(street) = animation {
                animationStreet = street
            }
            try refreshProjection(animation: publishedAnimation)
            state = animationState(
                from: state,
                event: publishedAnimation,
                visibleCards: visibleCards,
                visibleCommunityCards: visibleCommunityCards
            )
            if !winnerSeats.isEmpty {
                state = stateReplacing(winners: winnerSeats)
            }
            try await dependencies.sleep(
                CashTableAnimationTiming.duration(
                    for: animation,
                    street: animationStreet,
                    reduceMotion: dependencies.reduceMotion
                )
            )
            guard isCurrentOperation(operationVersion) else { return false }
        }
        return true
    }

    private func animationState(
        from projected: TableViewState,
        event: TableAnimationEvent,
        visibleCards: [SeatID: [TableCardState]],
        visibleCommunityCards: [Card]
    ) -> TableViewState {
        let phase: TableFlowPhase
        switch event.kind {
        case .dealHoleCard, .postBlind:
            phase = .dealing
        case .revealCommunityCard, .streetChanged:
            phase = .revealingBoard
        case .awardPot, .highlightWinner, .returnUncalledBet:
            phase = .settling
        case .showAction, .moveCommitmentToPot:
            phase = .animatingAction
        }
        let seats = projected.seats.map { seat in
            TableSeatState(
                id: seat.id,
                displayName: seat.displayName,
                isHuman: seat.isHuman,
                stack: seat.stack,
                committedThisStreet: seat.committedThisStreet,
                hasFolded: seat.hasFolded,
                isAllIn: seat.isAllIn,
                isDealer: seat.isDealer,
                isCurrentActor: false,
                cards: visibleCards[seat.id] ?? []
            )
        }
        return TableViewState(
            handID: projected.handID,
            stateVersion: projected.stateVersion,
            animationSequence: projected.animationSequence,
            phase: phase,
            seats: seats,
            communityCards: visibleCommunityCards,
            pot: projected.pot,
            controls: nil,
            secondsRemaining: nil,
            winners: projected.winners,
            errorMessage: projected.errorMessage,
            animation: projected.animation
        )
    }

    private func transitionSnapshot() -> CashTableAnimationSnapshot {
        guard let observation = store.spectatorObservation else {
            return CashTableAnimationSnapshot(
                commitments: [:],
                stacks: [:],
                currentBet: Chips(rawValue: 0)!
            )
        }
        return CashTableAnimationSnapshot(
            commitments: Dictionary(uniqueKeysWithValues: observation.publicSeats.map {
                ($0.id, $0.committedThisStreet)
            }),
            stacks: Dictionary(uniqueKeysWithValues: observation.publicSeats.map {
                ($0.id, $0.stack)
            }),
            currentBet: observation.currentBet
        )
    }

    private func applyCommittedSettlementState() {
        let stacks = Dictionary(uniqueKeysWithValues:
            (store.cashSession?.seats ?? []).map { ($0.id, $0.stack) }
        )
        let seats = state.seats.map { seat in
            TableSeatState(
                id: seat.id,
                displayName: seat.displayName,
                isHuman: seat.isHuman,
                stack: stacks[seat.id] ?? seat.stack,
                committedThisStreet: Chips(rawValue: 0)!,
                hasFolded: seat.hasFolded,
                isAllIn: (stacks[seat.id] ?? seat.stack).rawValue == 0,
                isDealer: seat.isDealer,
                isCurrentActor: false,
                cards: seat.cards
            )
        }
        state = TableViewState(
            handID: state.handID,
            stateVersion: stateVersion,
            animationSequence: animationSequence,
            phase: .awaitingNextHand,
            seats: seats,
            communityCards: state.communityCards,
            pot: state.pot,
            controls: nil,
            secondsRemaining: nil,
            winners: state.winners,
            errorMessage: nil,
            animation: state.animation
        )
    }

    private func isCurrentOperation(_ operationVersion: Int) -> Bool {
        stateVersion == operationVersion && state.phase != .suspended
    }

    private func cancelCountdown() {
        countdownTask.cancel()
    }

    private func cancelBotDecision() {
        let cancelledBotTask = botTask.cancel()
        guard let handID = currentHandID?.rawValue else { return }
        let service = botService
        let previousCancellation = botCancellationTask
        botCancellationGeneration &+= 1
        botCancellationTask = Task {
            await previousCancellation?.value
            await service.cancel(handID: handID)
            await cancelledBotTask?.value
        }
    }

    private func finishPendingBotCancellation() async {
        while let cancellation = botCancellationTask {
            let generation = botCancellationGeneration
            await cancellation.value
            guard generation == botCancellationGeneration else { continue }
            botCancellationTask = nil
            return
        }
    }

    private func showBotError() {
        botTask.clear()
        state = TableViewState(
            handID: state.handID,
            stateVersion: stateVersion,
            animationSequence: animationSequence,
            phase: state.phase,
            seats: state.seats,
            communityCards: state.communityCards,
            pot: state.pot,
            controls: nil,
            secondsRemaining: nil,
            winners: state.winners,
            errorMessage: "机器人行动失败，请重试。",
            animation: state.animation
        )
    }

    private func replacingState(
        phase: TableFlowPhase? = nil,
        secondsRemaining: Int?
    ) -> TableViewState {
        TableViewState(
            handID: state.handID,
            stateVersion: stateVersion,
            animationSequence: animationSequence,
            phase: phase ?? state.phase,
            seats: state.seats,
            communityCards: state.communityCards,
            pot: state.pot,
            controls: state.controls,
            secondsRemaining: secondsRemaining,
            winners: state.winners,
            errorMessage: state.errorMessage,
            animation: state.animation
        )
    }

    private func stateReplacing(
        phase: TableFlowPhase? = nil,
        winners: Set<SeatID>? = nil,
        errorMessage: String? = nil
    ) -> TableViewState {
        TableViewState(
            handID: state.handID,
            stateVersion: stateVersion,
            animationSequence: animationSequence,
            phase: phase ?? state.phase,
            seats: state.seats,
            communityCards: state.communityCards,
            pot: state.pot,
            controls: state.controls,
            secondsRemaining: state.secondsRemaining,
            winners: winners ?? state.winners,
            errorMessage: errorMessage,
            animation: state.animation
        )
    }

    nonisolated package static func oneHundredBigBlindBotTarget(
        for bigBlind: Chips
    ) throws -> Chips {
        let (rawTarget, overflow) = bigBlind.rawValue.multipliedReportingOverflow(by: 100)
        guard !overflow, let target = Chips(rawValue: rawTarget) else {
            throw PokerCoordinatorError.chipArithmeticOverflow
        }
        return target
    }

    nonisolated package static func requireBotPlayerObservation(
        _ observation: PlayerObservation?
    ) throws -> PlayerObservation {
        guard let observation else {
            throw PokerCoordinatorError.missingObservation
        }
        return observation
    }
}

private enum CountdownTickResult {
    case continueCountdown
    case performTimeout
    case stop
}

private final class CountdownTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func replace(with newTask: Task<Void, Never>?) {
        let oldTask = lock.withLock {
            let oldTask = task
            task = newTask
            return oldTask
        }
        oldTask?.cancel()
    }

    func cancel() {
        replace(with: nil)
    }

    func clear() {
        lock.withLock { task = nil }
    }
}

private final class BotTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    @discardableResult
    func replace(with newTask: Task<Void, Never>?) -> Task<Void, Never>? {
        let oldTask = lock.withLock {
            let oldTask = task
            task = newTask
            return oldTask
        }
        oldTask?.cancel()
        return oldTask
    }

    @discardableResult
    func cancel() -> Task<Void, Never>? {
        replace(with: nil)
    }

    func clear() {
        lock.withLock { task = nil }
    }
}
