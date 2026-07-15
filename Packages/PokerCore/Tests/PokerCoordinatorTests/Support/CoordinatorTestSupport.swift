import Foundation
import PokerBot
import PokerCore
import PokerSession
import Testing
@testable import PokerCoordinator

func decodeLegalActions(_ json: String) throws -> LegalActionSet {
    try JSONDecoder().decode(LegalActionSet.self, from: Data(json.utf8))
}

func decodeCards(_ json: String) throws -> [Card] {
    try JSONDecoder().decode([Card].self, from: Data(json.utf8))
}

func makeSafeTableViewState() throws -> TableViewState {
    let humanSeat = try SeatID(0)
    let botSeat = try SeatID(1)
    let aceOfSpades = try #require(
        Card.fullDeck.first { $0.rank == .ace && $0.suit == .spades }
    )
    let kingOfSpades = try #require(
        Card.fullDeck.first { $0.rank == .king && $0.suit == .spades }
    )
    let queenOfHearts = try #require(
        Card.fullDeck.first { $0.rank == .queen && $0.suit == .hearts }
    )
    return TableViewState(
        handID: "safe-hand",
        stateVersion: 1,
        animationSequence: 1,
        phase: .waitingForHuman,
        seats: [
            TableSeatState(
                id: humanSeat,
                displayName: "玩家",
                isHuman: true,
                stack: try Chips(3_800),
                committedThisStreet: try Chips(200),
                hasFolded: false,
                isAllIn: false,
                isDealer: true,
                isCurrentActor: true,
                cards: [
                    .faceUp(aceOfSpades),
                    .faceUp(kingOfSpades),
                ]
            ),
            TableSeatState(
                id: botSeat,
                displayName: "机器人",
                isHuman: false,
                stack: try Chips(3_400),
                committedThisStreet: try Chips(600),
                hasFolded: false,
                isAllIn: false,
                isDealer: false,
                isCurrentActor: false,
                cards: [.faceDown, .faceDown]
            ),
        ],
        communityCards: [queenOfHearts],
        pot: try Chips(800),
        controls: nil,
        secondsRemaining: 12,
        winners: [],
        errorMessage: nil,
        animation: .dealHoleCard(seat: botSeat, card: .faceDown)
    )
}

final class CoordinatorStoreFixture {
    let store: LocalPokerStore
    let humanSeat: SeatID
    let seatProfiles: [TableSeatProfile]
    let bustedBot: SeatID
    let showdownSeat: SeatID
    let foldedSeat: SeatID
    let completedRecord: CompletedHandRecord

    private let directory: URL

    private init(
        store: LocalPokerStore,
        humanSeat: SeatID,
        seatProfiles: [TableSeatProfile],
        bustedBot: SeatID,
        showdownSeat: SeatID,
        foldedSeat: SeatID,
        completedRecord: CompletedHandRecord,
        directory: URL
    ) {
        self.store = store
        self.humanSeat = humanSeat
        self.seatProfiles = seatProfiles
        self.bustedBot = bustedBot
        self.showdownSeat = showdownSeat
        self.foldedSeat = foldedSeat
        self.completedRecord = completedRecord
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    static func finishedHandWithBustedBot(
        smallBlind: Int = 50,
        bigBlind: Int = 100
    ) throws -> CoordinatorStoreFixture {
        let directory = try makeTemporaryDirectory(named: "finished-busted-bot")
        do {
            let lowStackBot = try SeatID(1)
            let store = try makeSeatedStore(
                directory: directory,
                botStackOverrides: [lowStackBot: try Chips(1)],
                smallBlind: smallBlind,
                bigBlind: bigBlind
            )
            try playToShowdown(in: store, foldedSeat: nil, seed: 7)
            let record = try pendingRecord(in: directory)
            let humanSeat = try SeatID(0)
            let bustedBot = try #require(
                record.finalStacks.keys.sorted().first {
                    $0 != humanSeat && record.finalStacks[$0]?.rawValue == 0
                }
            )
            _ = try store.commitPendingHand(transactionID: try BusinessID("settle-busted-bot"))
            let showdownSeat = try #require(
                record.handRanksBySeat.keys.sorted().first { $0 != bustedBot }
            )
            return CoordinatorStoreFixture(
                store: store,
                humanSeat: humanSeat,
                seatProfiles: try makeSeatProfiles(),
                bustedBot: bustedBot,
                showdownSeat: showdownSeat,
                foldedSeat: try SeatID(3),
                completedRecord: record,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func pendingShowdown() throws -> CoordinatorStoreFixture {
        let directory = try makeTemporaryDirectory(named: "pending-showdown")
        do {
            let foldedSeat = try SeatID(3)
            let store = try makeSeatedStore(directory: directory)
            try playToShowdown(in: store, foldedSeat: foldedSeat, seed: 11)
            let record = try pendingRecord(in: directory)
            let showdownSeat = try #require(
                record.handRanksBySeat.keys.sorted().first { $0 != foldedSeat }
            )
            return CoordinatorStoreFixture(
                store: store,
                humanSeat: try SeatID(0),
                seatProfiles: try makeSeatProfiles(),
                bustedBot: try SeatID(1),
                showdownSeat: showdownSeat,
                foldedSeat: foldedSeat,
                completedRecord: record,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func readyWithBustedBot(
        smallBlind: Int = 50,
        bigBlind: Int = 100
    ) throws -> CoordinatorStoreFixture {
        try finishedHandWithBustedBot(smallBlind: smallBlind, bigBlind: bigBlind)
    }
}

final class FailOnceSessionRepository: SessionRepository {
    private var state = PersistedAppState()
    private var shouldFailSettlement: Bool
    private var attemptedIDs: [BusinessID] = []

    init(failSettlementOnce: Bool = true) {
        shouldFailSettlement = failSettlementOnce
    }

    func load() throws -> PersistedAppState { state }

    func save(_ state: PersistedAppState) throws {
        if let businessID = state.settlementReceipts.keys.first {
            attemptedIDs.append(businessID)
            if shouldFailSettlement {
                shouldFailSettlement = false
                throw PokerSessionError.persistenceFailed
            }
        }
        self.state = state
    }

    func attemptedBusinessIDs() -> [BusinessID] { attemptedIDs }
}

final class BusinessIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var generated: [BusinessID] = []

    func next(for purpose: String) throws -> BusinessID {
        try lock.withLock {
            let id = try BusinessID("\(purpose)-\(generated.count + 1)")
            generated.append(id)
            return id
        }
    }

    func values() -> [BusinessID] {
        lock.withLock { generated }
    }
}

actor AnimationSleepRecorder {
    private var durations: [Duration] = []

    func sleep(for duration: Duration) {
        durations.append(duration)
    }

    func animationDurations() -> [Duration] {
        durations.filter { $0 < .seconds(1) }
    }
}

struct AnimationPublication: Equatable {
    let sequence: Int
    let event: TableAnimationEvent
    let stateVersion: Int
}

@MainActor
final class AnimationPublicationRecorder {
    weak var coordinator: CashTableCoordinator?
    private(set) var publications: [AnimationPublication] = []

    func capture() {
        guard let state = coordinator?.state,
              let event = state.animation
        else { return }
        publications.append(
            AnimationPublication(
                sequence: state.animationSequence,
                event: event,
                stateVersion: state.stateVersion
            )
        )
    }
}

private let coordinatorClock = FixedSessionClock(
    now: Date(timeIntervalSince1970: 1_752_499_800),
    day: try! LocalDay("2026-07-14")
)

private func makeTemporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "river-club-coordinator-\(name)-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

private func makeSeatedStore(
    directory: URL,
    botStackOverrides: [SeatID: Chips] = [:],
    smallBlind: Int = 50,
    bigBlind: Int = 100,
    dealer: SeatID? = nil
) throws -> LocalPokerStore {
    let humanSeat = try SeatID(0)
    let stacks = try Dictionary(uniqueKeysWithValues: (0..<9).map { rawSeat in
        let seat = try SeatID(rawSeat)
        let stack = try botStackOverrides[seat] ?? Chips(4_000)
        return (seat, stack)
    })
    let request = CashTableRequest(
        sessionID: try SessionID("coordinator-session"),
        table: try TableID("coordinator-table"),
        config: try HandConfig(
            smallBlind: try Chips(smallBlind),
            bigBlind: try Chips(bigBlind),
            dealer: dealer ?? humanSeat
        ),
        humanSeat: humanSeat,
        stacks: stacks
    )
    let store = try LocalPokerStore.open(directory: directory, clock: coordinatorClock)
    _ = try store.sitDown(
        request: request,
        businessID: try BusinessID("coordinator-buy-in")
    )
    return store
}

actor ManualTableClock {
    private struct Waiter {
        let deadline: Int64
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var now: Int64 = 0
    private var waiters: [UUID: Waiter] = [:]
    private var sleepCalls = 0
    private let onWaiterRegistered: @Sendable (ManualTableClock) -> Void
    private let advanceImmediatelyOnRegistration: Bool

    init(
        advanceImmediatelyOnRegistration: Bool = false,
        onWaiterRegistered: @escaping @Sendable (ManualTableClock) -> Void = { _ in }
    ) {
        self.advanceImmediatelyOnRegistration = advanceImmediatelyOnRegistration
        self.onWaiterRegistered = onWaiterRegistered
    }

    func sleep(for duration: Duration) async throws {
        sleepCalls += 1
        let seconds = duration.components.seconds
        guard seconds > 0 else { return }
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = Waiter(deadline: now + seconds, continuation: continuation)
                onWaiterRegistered(self)
                if Task.isCancelled {
                    cancel(id)
                    return
                }
                if advanceImmediatelyOnRegistration,
                   let waiter = waiters.removeValue(forKey: id) {
                    now += seconds
                    waiter.continuation.resume()
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
        try Task.checkCancellation()
    }

    func sleepCallCount() -> Int {
        sleepCalls
    }

    func waitUntilScheduled() async {
        while waiters.isEmpty { await Task.yield() }
    }

    func waiterCount() -> Int {
        waiters.count
    }

    func waitUntilIdle() async {
        while !waiters.isEmpty { await Task.yield() }
    }

    func advance(by duration: Duration) async {
        let seconds = max(0, duration.components.seconds)
        for _ in 0..<seconds {
            advanceOneSecond()
        }
    }

    func advanceOneSecond() {
        now += 1
        let due = waiters.filter { $0.value.deadline <= now }
        for (id, waiter) in due {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}

actor ManualAnimationGate {
    private var isEnabled = false
    private var isBlocked = false
    private var continuation: CheckedContinuation<Void, Never>?

    func enable() {
        isEnabled = true
    }

    func sleepIfEnabled() async {
        guard isEnabled else { return }
        isBlocked = true
        await withCheckedContinuation { continuation = $0 }
        isBlocked = false
    }

    func waitUntilBlocked() async {
        while !isBlocked { await Task.yield() }
    }

    func resume() {
        isEnabled = false
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class CoordinatorScenario {
    let coordinator: CashTableCoordinator
    let store: LocalPokerStore

    private let directory: URL

    private init(
        coordinator: CashTableCoordinator,
        store: LocalPokerStore,
        directory: URL
    ) {
        self.coordinator = coordinator
        self.store = store
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    static func readyToStartWithHumanFirst(
        clock: ManualTableClock,
        animationGate: ManualAnimationGate
    ) throws -> CoordinatorScenario {
        let directory = try makeTemporaryDirectory(named: "human-start-gate")
        do {
            let store = try makeSeatedStore(
                directory: directory,
                dealer: SeatID(6)
            )
            let humanSeat = try SeatID(0)
            let dependencies = TableRuntimeDependencies(
                nextHandID: { try HandID("human-start-gate-hand") },
                nextBusinessID: { purpose in try BusinessID("\(purpose)-human-start-gate") },
                nextSeed: { 23 },
                sleep: { duration in
                    if duration == .zero {
                        await animationGate.sleepIfEnabled()
                    } else {
                        try await clock.sleep(for: duration)
                    }
                },
                reduceMotion: true
            )
            let coordinator = try CashTableCoordinator(
                store: store,
                humanSeat: humanSeat,
                seatProfiles: try makeSeatProfiles(),
                dependencies: dependencies
            )
            return CoordinatorScenario(
                coordinator: coordinator,
                store: store,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func humanFacingRaise(
        clock: ManualTableClock = ManualTableClock()
    ) async throws -> CoordinatorScenario {
        try await make(clock: clock, dealer: SeatID(0)) { store, humanSeat in
            var raised = false
            while store.cashSession?.currentActor != humanSeat {
                let actor = try #require(store.cashSession?.currentActor)
                let observation = try #require(try store.playerObservation(for: actor))
                let legal = try #require(observation.legalActions)
                let action: PlayerAction
                if !raised, let minimum = legal.minimumRaiseTo {
                    action = .raiseTo(minimum)
                    raised = true
                } else if legal.canFold {
                    action = .fold
                } else {
                    action = .check
                }
                _ = try store.apply(action, by: actor)
            }
        }
    }

    static func humanCanRaiseToAllIn(
        clock: ManualTableClock = ManualTableClock()
    ) async throws -> CoordinatorScenario {
        try await make(clock: clock, dealer: SeatID(6)) { _, _ in }
    }

    static func humanCanBet(
        clock: ManualTableClock = ManualTableClock()
    ) async throws -> CoordinatorScenario {
        let dealer = try SeatID(8)
        return try await make(clock: clock, dealer: dealer) { store, humanSeat in
            while store.cashSession?.phase == .handInProgress {
                if let actor = store.cashSession?.currentActor {
                    let observation = try #require(try store.playerObservation(for: actor))
                    if actor == humanSeat, observation.street != .preflop { break }
                    let legal = try #require(observation.legalActions)
                    let action: PlayerAction
                    if actor == humanSeat, legal.callAmount != nil {
                        action = .call
                    } else if actor == dealer, legal.callAmount != nil {
                        action = .call
                    } else if legal.canCheck {
                        action = .check
                    } else if legal.canFold {
                        action = .fold
                    } else {
                        action = .call
                    }
                    _ = try store.apply(action, by: actor)
                } else {
                    _ = try store.advanceIfRoundComplete()
                    if store.cashSession?.currentActor == humanSeat { break }
                }
            }
        }
    }

    static func humanCanCheck(
        clock: ManualTableClock = ManualTableClock()
    ) async throws -> CoordinatorScenario {
        let smallBlindSeat = try SeatID(8)
        return try await make(clock: clock, dealer: SeatID(7)) { store, humanSeat in
            while store.cashSession?.currentActor != humanSeat {
                let actor = try #require(store.cashSession?.currentActor)
                let observation = try #require(try store.playerObservation(for: actor))
                let legal = try #require(observation.legalActions)
                let action: PlayerAction
                if actor == smallBlindSeat, legal.callAmount != nil {
                    action = .call
                } else if legal.canFold {
                    action = .fold
                } else {
                    action = .check
                }
                _ = try store.apply(action, by: actor)
            }
        }
    }

    static func humanFacingBlind(
        clock: ManualTableClock = ManualTableClock(),
        animationGate: ManualAnimationGate? = nil
    ) async throws -> CoordinatorScenario {
        try await make(
            clock: clock,
            dealer: SeatID(6),
            animationGate: animationGate
        ) { _, _ in }
    }

    static func botOpeningAction(
        botService: any BotDecisionServing,
        clock: ManualTableClock? = nil,
        seed: UInt64 = 31
    ) async throws -> CoordinatorScenario {
        let directory = try makeTemporaryDirectory(named: "bot-opening-action")
        do {
            let store = try makeSeatedStore(
                directory: directory,
                dealer: SeatID(0)
            )
            let coordinator = try CashTableCoordinator(
                store: store,
                humanSeat: SeatID(0),
                seatProfiles: try makeSeatProfiles(),
                dependencies: TableRuntimeDependencies(
                    nextHandID: { try HandID("bot-hand-\(seed)") },
                    nextBusinessID: { purpose in
                        try BusinessID("\(purpose)-bot-\(seed)")
                    },
                    nextSeed: { seed },
                    sleep: { duration in
                        try await clock?.sleep(for: duration)
                    },
                    reduceMotion: true
                ),
                botService: botService
            )
            try await coordinator.startHand(settings: .recommended)
            return CoordinatorScenario(
                coordinator: coordinator,
                store: store,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func botThinking(
        delayFirstCancellation: Bool = false
    ) async throws -> CoordinatorLifecycleFixture {
        let clock = ManualTableClock()
        let botService = LifecycleBotDecisionService(
            delayFirstCancellation: delayFirstCancellation
        )
        let scenario = try await botOpeningAction(
            botService: botService,
            clock: clock
        )
        _ = await botService.waitUntilRequestCount(1)
        return CoordinatorLifecycleFixture(
            scenario: scenario,
            clock: clock,
            botService: botService,
            versionBeforeSuspend: scenario.coordinator.state.stateVersion
        )
    }

    static func pendingSettlement(
        repository: FailOnceSessionRepository,
        businessIDs: BusinessIDSequence = BusinessIDSequence(),
        failBusinessIDGeneration: Bool = false
    ) async throws -> CoordinatorScenario {
        let directory = try makeTemporaryDirectory(named: "pending-settlement")
        do {
            let humanSeat = try SeatID(0)
            let store = try makeSeatedStore(repository: repository)
            let coordinator = try CashTableCoordinator(
                store: store,
                humanSeat: humanSeat,
                seatProfiles: try makeSeatProfiles(),
                dependencies: TableRuntimeDependencies(
                    nextHandID: { try HandID("pending-settlement-\(UUID().uuidString)") },
                    nextBusinessID: { purpose in
                        if failBusinessIDGeneration {
                            throw PokerCoordinatorError.saveFailed
                        }
                        return try businessIDs.next(for: purpose)
                    },
                    nextSeed: { 41 },
                    sleep: { _ in }
                )
            )
            try await coordinator.startHand(settings: .recommended)
            try playExistingHandToShowdown(
                in: store,
                foldedSeat: try SeatID(3)
            )
            return CoordinatorScenario(
                coordinator: coordinator,
                store: store,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func automaticSettlement(
        repository: FailOnceSessionRepository,
        businessIDs: BusinessIDSequence = BusinessIDSequence(),
        animationRecorder: AnimationSleepRecorder? = nil,
        reduceMotion: Bool = true
    ) async throws -> CoordinatorScenario {
        let directory = try makeTemporaryDirectory(named: "automatic-settlement")
        do {
            let humanSeat = try SeatID(0)
            let store = try makeSeatedStore(repository: repository)
            let coordinator = try CashTableCoordinator(
                store: store,
                humanSeat: humanSeat,
                seatProfiles: try makeSeatProfiles(),
                dependencies: TableRuntimeDependencies(
                    nextHandID: {
                        try HandID("automatic-settlement-\(UUID().uuidString)")
                    },
                    nextBusinessID: businessIDs.next,
                    nextSeed: { 43 },
                    sleep: { duration in
                        await animationRecorder?.sleep(for: duration)
                    },
                    reduceMotion: reduceMotion
                )
            )
            try await coordinator.startHand(settings: .recommended)
            return CoordinatorScenario(
                coordinator: coordinator,
                store: store,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func pendingSettlementWithoutRanks() async throws -> CoordinatorScenario {
        let repository = FailOnceSessionRepository(failSettlementOnce: false)
        let scenario = try await pendingSettlementBase(repository: repository)
        try foldExistingHandToOneWinner(in: scenario.store)
        return scenario
    }

    private static func pendingSettlementBase(
        repository: FailOnceSessionRepository
    ) async throws -> CoordinatorScenario {
        let directory = try makeTemporaryDirectory(named: "pending-without-ranks")
        do {
            let humanSeat = try SeatID(0)
            let store = try makeSeatedStore(repository: repository)
            let coordinator = try CashTableCoordinator(
                store: store,
                humanSeat: humanSeat,
                seatProfiles: try makeSeatProfiles(),
                dependencies: TableRuntimeDependencies(
                    nextHandID: { try HandID("pending-without-ranks") },
                    nextBusinessID: { purpose in
                        try BusinessID("\(purpose)-without-ranks")
                    },
                    nextSeed: { 47 },
                    sleep: { _ in },
                    reduceMotion: true
                )
            )
            try await coordinator.startHand(settings: .recommended)
            return CoordinatorScenario(
                coordinator: coordinator,
                store: store,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func actionCount() throws -> Int {
        try #require(try store.humanObservation()).actions.count
    }

    func playDeterministicallyToSettlement() async throws {
        var remainingSteps = 300
        while store.cashSession?.phase == .handInProgress, remainingSteps > 0 {
            remainingSteps -= 1
            try await coordinator.runUntilHumanOrSettlement()
            guard store.cashSession?.phase == .handInProgress else { break }
            let observation = try #require(try store.humanObservation())
            guard observation.currentActor == observation.viewer,
                  let legal = observation.legalActions
            else {
                await Task.yield()
                continue
            }
            if legal.canCheck || legal.callAmount != nil {
                try await coordinator.send(.middle)
            } else {
                try await coordinator.send(.fold)
            }
        }
        #expect(remainingSteps > 0)
    }

    func waitForAutomaticSettlement() async {
        for _ in 0..<10_000 {
            if coordinator.state.phase == .awaitingNextHand
                || coordinator.state.phase == .saveFailed {
                return
            }
            await Task.yield()
        }
    }

    private static func make(
        clock: ManualTableClock,
        dealer: SeatID,
        stackOverrides: [SeatID: Chips] = [:],
        animationGate: ManualAnimationGate? = nil,
        prepare: @escaping @MainActor (LocalPokerStore, SeatID) throws -> Void
    ) async throws -> CoordinatorScenario {
        let directory = try makeTemporaryDirectory(named: "human-action")
        do {
            let store = try makeSeatedStore(
                directory: directory,
                botStackOverrides: stackOverrides,
                dealer: dealer
            )
            let humanSeat = try SeatID(0)
            let hook = OneShotPreparation {
                try prepare(store, humanSeat)
            }
            let dependencies = TableRuntimeDependencies(
                nextHandID: { try HandID("human-action-hand") },
                nextBusinessID: { purpose in try BusinessID("\(purpose)-human-action") },
                nextSeed: { 17 },
                sleep: { duration in
                    if duration == .zero {
                        try await hook.run()
                        await animationGate?.sleepIfEnabled()
                    } else {
                        try await clock.sleep(for: duration)
                    }
                },
                reduceMotion: true
            )
            let coordinator = try CashTableCoordinator(
                store: store,
                humanSeat: humanSeat,
                seatProfiles: try makeSeatProfiles(),
                dependencies: dependencies
            )
            try await coordinator.startHand(settings: .recommended)
            await clock.waitUntilScheduled()
            return CoordinatorScenario(
                coordinator: coordinator,
                store: store,
                directory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

@MainActor
final class CoordinatorLifecycleFixture {
    let scenario: CoordinatorScenario
    let clock: ManualTableClock
    let botService: LifecycleBotDecisionService
    let versionBeforeSuspend: Int

    var coordinator: CashTableCoordinator {
        scenario.coordinator
    }

    init(
        scenario: CoordinatorScenario,
        clock: ManualTableClock,
        botService: LifecycleBotDecisionService,
        versionBeforeSuspend: Int
    ) {
        self.scenario = scenario
        self.clock = clock
        self.botService = botService
        self.versionBeforeSuspend = versionBeforeSuspend
    }

    func actionCount() throws -> Int {
        try scenario.actionCount()
    }
}

private func makeSeatedStore(
    repository: any SessionRepository
) throws -> LocalPokerStore {
    let humanSeat = try SeatID(0)
    let stacks = try Dictionary(uniqueKeysWithValues: (0..<9).map {
        (try SeatID($0), try Chips(4_000))
    })
    let store = try LocalPokerStore(repository: repository, clock: coordinatorClock)
    _ = try store.sitDown(
        request: CashTableRequest(
            sessionID: try SessionID("settlement-session"),
            table: try TableID("settlement-table"),
            config: try HandConfig(
                smallBlind: try Chips(50),
                bigBlind: try Chips(100),
                dealer: try SeatID(0)
            ),
            humanSeat: humanSeat,
            stacks: stacks
        ),
        businessID: try BusinessID("settlement-buy-in")
    )
    return store
}

private func playExistingHandToShowdown(
    in store: LocalPokerStore,
    foldedSeat: SeatID
) throws {
    var hasFoldedDesignatedSeat = false
    var remainingSteps = 200
    while store.cashSession?.phase == .handInProgress, remainingSteps > 0 {
        remainingSteps -= 1
        if let actor = store.cashSession?.currentActor {
            let observation = try #require(try store.playerObservation(for: actor))
            let legal = try #require(observation.legalActions)
            let action: PlayerAction
            if actor == foldedSeat, !hasFoldedDesignatedSeat, legal.canFold {
                action = .fold
                hasFoldedDesignatedSeat = true
            } else if legal.canCheck {
                action = .check
            } else if legal.callAmount != nil {
                action = .call
            } else {
                action = .fold
            }
            _ = try store.apply(action, by: actor)
        } else {
            _ = try store.advanceIfRoundComplete()
        }
    }
    #expect(remainingSteps > 0)
    #expect(hasFoldedDesignatedSeat)
    #expect(store.cashSession?.phase == .settlementPending)
}

private func foldExistingHandToOneWinner(in store: LocalPokerStore) throws {
    var remainingSteps = 30
    while store.cashSession?.phase == .handInProgress, remainingSteps > 0 {
        remainingSteps -= 1
        if let actor = store.cashSession?.currentActor {
            let observation = try #require(try store.playerObservation(for: actor))
            let legal = try #require(observation.legalActions)
            let action: PlayerAction
            if legal.canFold {
                action = .fold
            } else if legal.canCheck {
                action = .check
            } else {
                action = .call
            }
            _ = try store.apply(action, by: actor)
        } else {
            _ = try store.advanceIfRoundComplete()
        }
    }
    #expect(remainingSteps > 0)
    #expect(store.cashSession?.phase == .settlementPending)
}

actor RecordingBotDecisionService: BotDecisionServing {
    private var recordedRequests: [BotDecisionRequest] = []
    private var returnedActions: [PlayerAction] = []
    private var activeCalls = 0
    private var maximumCalls = 0

    func decide(_ request: BotDecisionRequest) async -> BotDecision? {
        activeCalls += 1
        maximumCalls = max(maximumCalls, activeCalls)
        recordedRequests.append(request)
        defer { activeCalls -= 1 }
        await Task.yield()
        let legal = request.observation.legalActions
        let action: PlayerAction
        if legal.canCheck {
            action = .check
        } else if legal.callAmount != nil {
            action = .call
        } else if legal.canFold {
            action = .fold
        } else {
            return nil
        }
        returnedActions.append(action)
        return BotDecision(
            action: action,
            handID: request.observation.handID,
            stateVersion: request.observation.stateVersion,
            reason: .ruleEvaluation,
            simulationIterations: 0
        )
    }

    func cancel(handID: String) async {}

    func requests() -> [BotDecisionRequest] {
        recordedRequests
    }

    func maximumConcurrentCalls() -> Int {
        maximumCalls
    }

    func actions() -> [PlayerAction] {
        returnedActions
    }
}

actor SuspendedBotDecisionService: BotDecisionServing {
    private var request: BotDecisionRequest?
    private var continuation: CheckedContinuation<BotDecision?, Never>?
    private var cancelledHands: [String] = []
    private var receivedRequests = 0

    func decide(_ request: BotDecisionRequest) async -> BotDecision? {
        receivedRequests += 1
        self.request = request
        return await withCheckedContinuation { continuation = $0 }
    }

    func cancel(handID: String) async {
        cancelledHands.append(handID)
    }

    func waitUntilRequested() async {
        while request == nil { await Task.yield() }
    }

    func waitUntilCancelled() async {
        while cancelledHands.isEmpty { await Task.yield() }
    }

    func requestCount() -> Int {
        receivedRequests
    }

    func resume(
        with action: PlayerAction,
        stateVersion: Int,
        handID: String? = nil
    ) {
        guard let request else { return }
        continuation?.resume(returning: BotDecision(
            action: action,
            handID: handID ?? request.observation.handID,
            stateVersion: stateVersion,
            reason: .ruleEvaluation,
            simulationIterations: 0
        ))
        continuation = nil
    }
}

actor LifecycleBotDecisionService: BotDecisionServing {
    private(set) var cancelCount = 0
    private var requestCount = 0
    private var activeCalls = 0
    private var maximumCalls = 0
    private var decisionContinuations: [UUID: CheckedContinuation<BotDecision?, Never>] = [:]
    private var shouldDelayNextCancellation: Bool
    private var cancellationStarted = false
    private var cancellationRelease: CheckedContinuation<Void, Never>?

    init(delayFirstCancellation: Bool = false) {
        shouldDelayNextCancellation = delayFirstCancellation
    }

    func decide(_ request: BotDecisionRequest) async -> BotDecision? {
        let id = UUID()
        requestCount += 1
        activeCalls += 1
        maximumCalls = max(maximumCalls, activeCalls)
        let decision = await withCheckedContinuation { continuation in
            decisionContinuations[id] = continuation
        }
        activeCalls -= 1
        return decision
    }

    func cancel(handID: String) async {
        let pendingIDs = Array(decisionContinuations.keys)
        cancelCount += 1
        cancellationStarted = true
        if shouldDelayNextCancellation {
            shouldDelayNextCancellation = false
            await withCheckedContinuation { continuation in
                cancellationRelease = continuation
            }
        }
        for id in pendingIDs {
            decisionContinuations.removeValue(forKey: id)?.resume(returning: nil)
        }
    }

    func waitUntilCancelled() async {
        while cancelCount == 0 { await Task.yield() }
    }

    func waitUntilIdle() async {
        while activeCalls != 0 { await Task.yield() }
    }

    func waitUntilRequestCount(
        _ expectedCount: Int,
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while requestCount < expectedCount, clock.now < deadline {
            await Task.yield()
        }
        return requestCount >= expectedCount
    }

    func waitUntilCancellationStarted(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !cancellationStarted, clock.now < deadline {
            await Task.yield()
        }
        return cancellationStarted
    }

    func releaseCancellation() {
        cancellationRelease?.resume()
        cancellationRelease = nil
    }

    func finishAllDecisions() {
        let continuations = decisionContinuations.values
        decisionContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: nil)
        }
    }

    func maximumConcurrentCalls() -> Int {
        maximumCalls
    }
}

actor NilBotDecisionService: BotDecisionServing {
    private var recordedRequests: [BotDecisionRequest] = []

    func decide(_ request: BotDecisionRequest) async -> BotDecision? {
        recordedRequests.append(request)
        return nil
    }

    func cancel(handID: String) async {}

    func requests() -> [BotDecisionRequest] {
        recordedRequests
    }
}

private actor OneShotPreparation {
    private var didRun = false
    private let body: @MainActor () throws -> Void

    init(body: @escaping @MainActor () throws -> Void) {
        self.body = body
    }

    func run() async throws {
        guard !didRun else { return }
        didRun = true
        try await body()
    }
}

private func makeSeatProfiles() throws -> [TableSeatProfile] {
    try (0..<9).map { rawSeat in
        try TableSeatProfile(
            id: SeatID(rawSeat),
            displayName: rawSeat == 0 ? "玩家" : "机器人 \(rawSeat)"
        )
    }
}

private func playToShowdown(
    in store: LocalPokerStore,
    foldedSeat: SeatID?,
    seed: UInt64
) throws {
    _ = try store.startHand(id: try HandID("coordinator-hand"), seed: seed)
    var hasFoldedDesignatedSeat = false
    var remainingSteps = 200

    while store.cashSession?.phase == .handInProgress, remainingSteps > 0 {
        remainingSteps -= 1
        if let actor = store.cashSession?.currentActor {
            let observation = try #require(try store.playerObservation(for: actor))
            let legal = try #require(observation.legalActions)
            let action: PlayerAction
            if actor == foldedSeat, !hasFoldedDesignatedSeat, legal.canFold {
                action = .fold
                hasFoldedDesignatedSeat = true
            } else if legal.canCheck {
                action = .check
            } else if legal.callAmount != nil {
                action = .call
            } else {
                action = .fold
            }
            _ = try store.apply(action, by: actor)
        } else {
            _ = try store.advanceIfRoundComplete()
        }
    }

    #expect(remainingSteps > 0)
    #expect(store.cashSession?.phase == .settlementPending)
    if foldedSeat != nil {
        #expect(hasFoldedDesignatedSeat)
    }
}

private func pendingRecord(in directory: URL) throws -> CompletedHandRecord {
    try #require(
        FileSessionRepository(directory: directory)
            .load()
            .activeCashSession?
            .pendingHand?
            .record
    )
}
