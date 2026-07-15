import PokerBot
import PokerCore
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

@Test @MainActor func 初始化拒绝缺少座位资料() throws {
    let fixture = try CoordinatorStoreFixture.readyWithBustedBot()
    let profiles = Array(fixture.seatProfiles.dropLast())

    #expect(throws: PokerCoordinatorError.missingObservation) {
        try CashTableCoordinator(
            store: fixture.store,
            humanSeat: fixture.humanSeat,
            seatProfiles: profiles,
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
