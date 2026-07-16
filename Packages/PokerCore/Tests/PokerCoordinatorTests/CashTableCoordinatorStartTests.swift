import PokerBot
import PokerCore
import PokerSession
import Testing
@testable import PokerCoordinator

@Test @MainActor func 开始手牌自动补充机器人并发布安全发牌状态() async throws {
    let bigBlind = 80
    let fixture = try CoordinatorStoreFixture.readyWithBustedBot(
        smallBlind: 40,
        bigBlind: bigBlind
    )
    let balanceBefore = fixture.store.accountBalance
    let humanStackBefore = try #require(
        fixture.store.cashSession?.seats.first { $0.id == fixture.humanSeat }?.stack
    )
    let unchangedBot = try SeatID(8)
    let unchangedBotStackBefore = try #require(
        fixture.store.cashSession?.seats.first { $0.id == unchangedBot }?.stack
    )
    let coordinator = try CashTableCoordinator(
        store: fixture.store,
        humanSeat: fixture.humanSeat,
        seatProfiles: fixture.seatProfiles,
        archiveMetadata: makeCoordinatorArchiveMetadata(),
        dependencies: .immediate(seed: 7)
    )

    try await coordinator.startHand(settings: .recommended)
    let refillTarget = try Chips(bigBlind * 100)
    let humanObservation = try #require(try fixture.store.humanObservation())
    let humanCards = try #require(
        coordinator.state.seats.first { $0.id == fixture.humanSeat }?.cards
    )

    #expect(coordinator.state.handID == "hand-1")
    #expect(coordinator.state.seats.count == 9)
    #expect(humanCards == humanObservation.ownHoleCards.map(TableCardState.faceUp))
    #expect(humanCards.count == 2)
    #expect(humanCards.allSatisfy {
        if case .faceUp = $0 { true } else { false }
    })
    #expect(coordinator.state.seats.filter { $0.id != fixture.humanSeat }.allSatisfy {
        $0.cards == [.faceDown, .faceDown]
    })
    #expect(coordinator.frozenSettings == .recommended)
    #expect(
        fixture.store.cashSession?.seats.first { $0.id == fixture.bustedBot }?.stack
            == refillTarget
    )
    #expect(fixture.store.accountBalance == balanceBefore)
    #expect(
        fixture.store.cashSession?.seats.first { $0.id == fixture.humanSeat }?.stack
            == humanStackBefore
    )
    #expect(
        fixture.store.cashSession?.seats.first { $0.id == unchangedBot }?.stack
            == unchangedBotStackBefore
    )
}

@Test @MainActor func 动画发布序号逐事件递增且不改写业务版本() async throws {
    let fixture = try CoordinatorStoreFixture.readyWithBustedBot()
    let recorder = AnimationPublicationRecorder()
    let coordinator = try CashTableCoordinator(
        store: fixture.store,
        humanSeat: fixture.humanSeat,
        seatProfiles: fixture.seatProfiles,
        archiveMetadata: makeCoordinatorArchiveMetadata(),
        dependencies: TableRuntimeDependencies(
            nextHandID: { try HandID("animation-sequence-hand") },
            nextBusinessID: { purpose in try BusinessID("\(purpose)-animation-sequence") },
            nextSeed: { 7 },
            sleep: { _ in await recorder.capture() },
            reduceMotion: true
        )
    )
    recorder.coordinator = coordinator

    try await coordinator.startHand(settings: .recommended)

    let publications = recorder.publications
    #expect(publications.count >= 2)
    #expect(publications.map(\.sequence) == Array(1...publications.count))
    #expect(Set(publications.map(\.stateVersion)).count == 1)
    #expect(hasRepeatedEvent(in: publications.map(\.event)))
}

private func hasRepeatedEvent(in events: [TableAnimationEvent]) -> Bool {
    for first in events.indices {
        for second in events.indices where second > first {
            if events[first] == events[second] { return true }
        }
    }
    return false
}

@Test @MainActor func 开局展示失败后暂停且恢复不重复开局() async throws {
    let fixture = try CoordinatorStoreFixture.readyWithBustedBot()
    let balanceBefore = fixture.store.accountBalance
    let coordinator = try CashTableCoordinator(
        store: fixture.store,
        humanSeat: fixture.humanSeat,
        seatProfiles: fixture.seatProfiles,
        archiveMetadata: makeCoordinatorArchiveMetadata(),
        dependencies: TableRuntimeDependencies(
            nextHandID: { try HandID("resume-hand") },
            nextBusinessID: { purpose in try BusinessID("\(purpose)-resume") },
            nextSeed: { 19 },
            sleep: { _ in throw CoordinatorStartupTestError.animationSleep },
            reduceMotion: true
        )
    )

    await #expect(throws: CoordinatorStartupTestError.animationSleep) {
        try await coordinator.startHand(settings: .recommended)
    }
    #expect(fixture.store.cashSession?.phase == .handInProgress)
    #expect(coordinator.state.phase == .suspended)

    try await coordinator.resume()

    #expect(fixture.store.cashSession?.phase == .handInProgress)
    #expect(coordinator.state.phase != .suspended)
    #expect(coordinator.state.handID == "resume-hand")
    #expect(fixture.store.accountBalance == balanceBefore)
}

@Test @MainActor func 初始化拒绝缺少座位资料() throws {
    let fixture = try CoordinatorStoreFixture.readyWithBustedBot()
    let profiles = Array(fixture.seatProfiles.dropLast())

    #expect(throws: PokerCoordinatorError.missingObservation) {
        try CashTableCoordinator(
            store: fixture.store,
            humanSeat: fixture.humanSeat,
            seatProfiles: profiles,
            archiveMetadata: makeCoordinatorArchiveMetadata(),
            dependencies: .immediate(seed: 7)
        )
    }
}

@Test @MainActor func 初始化拒绝重复座位资料() throws {
    let fixture = try CoordinatorStoreFixture.readyWithBustedBot()
    var profiles = fixture.seatProfiles
    profiles[profiles.count - 1] = profiles[0]

    #expect(throws: PokerCoordinatorError.missingObservation) {
        try CashTableCoordinator(
            store: fixture.store,
            humanSeat: fixture.humanSeat,
            seatProfiles: profiles,
            archiveMetadata: makeCoordinatorArchiveMetadata(),
            dependencies: .immediate(seed: 7)
        )
    }
}

@Test @MainActor func 初始化拒绝额外座位资料() throws {
    let fixture = try CoordinatorStoreFixture.readyWithBustedBot()
    let profiles = fixture.seatProfiles + [fixture.seatProfiles[0]]

    #expect(throws: PokerCoordinatorError.missingObservation) {
        try CashTableCoordinator(
            store: fixture.store,
            humanSeat: fixture.humanSeat,
            seatProfiles: profiles,
            archiveMetadata: makeCoordinatorArchiveMetadata(),
            dependencies: .immediate(seed: 7)
        )
    }
}

@Test func 一百大盲机器人目标筹码溢出时拒绝() throws {
    let overflowingBigBlind = try Chips(Int.max)

    #expect(throws: PokerCoordinatorError.chipArithmeticOverflow) {
        try CashTableCoordinator.oneHundredBigBlindBotTarget(
            for: overflowingBigBlind
        )
    }
}

private enum CoordinatorStartupTestError: Error {
    case animationSleep
}
