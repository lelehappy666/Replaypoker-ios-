import Testing
@testable import PokerCoordinator

@Test @MainActor
func 后台取消计时与机器人且前台只恢复当前行动() async throws {
    let fixture = try await CoordinatorScenario.botThinking()
    fixture.coordinator.suspend()
    await fixture.botService.waitUntilCancelled()
    await fixture.botService.waitUntilIdle()
    let actionCount = try fixture.actionCount()

    #expect(fixture.coordinator.state.phase == .suspended)
    #expect(await fixture.botService.cancelCount == 1)
    await fixture.clock.advance(by: .seconds(60))
    #expect(try fixture.actionCount() == actionCount)

    try await fixture.coordinator.resume()
    await fixture.botService.waitUntilRequestCount(2)

    #expect(fixture.coordinator.state.stateVersion > fixture.versionBeforeSuspend)
    #expect(await fixture.botService.maximumConcurrentCalls() == 1)
}
