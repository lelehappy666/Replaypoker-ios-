import PokerBot
import PokerCore
import Testing
@testable import PokerCoordinator

@Test @MainActor func 开始手牌自动补充机器人并发布安全发牌状态() async throws {
    let fixture = try CoordinatorStoreFixture.readyWithBustedBot()
    let coordinator = try CashTableCoordinator(
        store: fixture.store,
        humanSeat: fixture.humanSeat,
        seatProfiles: fixture.seatProfiles,
        dependencies: .immediate(seed: 7)
    )

    try await coordinator.startHand(settings: .recommended)
    let refillTarget = try Chips(10_000)

    #expect(coordinator.state.handID == "hand-1")
    #expect(coordinator.state.seats.count == 9)
    #expect(
        coordinator.state.seats.first { $0.id == fixture.humanSeat }?.cards.count == 2
    )
    #expect(coordinator.state.seats.filter { $0.id != fixture.humanSeat }.allSatisfy {
        $0.cards == [.faceDown, .faceDown]
    })
    #expect(coordinator.frozenSettings == .recommended)
    #expect(
        fixture.store.cashSession?.seats.first { $0.id == fixture.bustedBot }?.stack
            == refillTarget
    )
}
