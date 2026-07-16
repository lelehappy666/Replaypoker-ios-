import PokerCore
import PokerSession
import Testing
@testable import PokerCoordinator

@Test @MainActor func 进行中离桌自动弃牌保存记录并只退款一次() async throws {
    let scenario = try await CoordinatorScenario.humanFacingBlind()
    let settlementID = try BusinessID("departure-settlement")
    let cashOutID = try BusinessID("departure-cash-out")
    let balanceBefore = scenario.store.accountBalance

    try await scenario.coordinator.leaveTable(
        settlementID: settlementID,
        cashOutID: cashOutID
    )
    let balanceAfter = scenario.store.accountBalance

    #expect(scenario.store.cashSession == nil)
    #expect(scenario.store.handRecords().count == 1)
    #expect(balanceAfter > balanceBefore)
    #expect(
        scenario.store.handRecords()[0].record.actions.contains {
            $0.seat == (try? SeatID(0))
                && $0.action == .fold
                && $0.isDeparture
        }
    )

    try await scenario.coordinator.leaveTable(
        settlementID: settlementID,
        cashOutID: cashOutID
    )
    #expect(scenario.store.accountBalance == balanceAfter)
    #expect(scenario.store.handRecords().count == 1)
}
