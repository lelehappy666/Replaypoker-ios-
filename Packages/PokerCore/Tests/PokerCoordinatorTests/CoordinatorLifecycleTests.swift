import Testing
@testable import PokerCoordinator

@Test @MainActor
func 后台取消计时与机器人且前台只恢复当前行动() async throws {
    let fixture = try await CoordinatorScenario.botThinking()
    #expect(await fixture.clock.sleepCallCount() > 0)
    fixture.coordinator.suspend()
    await fixture.botService.waitUntilCancelled()
    await fixture.botService.waitUntilIdle()
    let actionCount = try fixture.actionCount()

    #expect(fixture.coordinator.state.phase == .suspended)
    #expect(await fixture.botService.cancelCount == 1)
    await fixture.clock.advance(by: .seconds(60))
    #expect(try fixture.actionCount() == actionCount)

    try await fixture.coordinator.resume()
    _ = await fixture.botService.waitUntilRequestCount(2)

    #expect(fixture.coordinator.state.stateVersion > fixture.versionBeforeSuspend)
    #expect(await fixture.botService.maximumConcurrentCalls() == 1)
}

@Test @MainActor
func 暂停后立即恢复也不会与旧机器人请求重叠() async throws {
    let fixture = try await CoordinatorScenario.botThinking(
        delayFirstCancellation: true
    )
    fixture.coordinator.suspend()
    let resumeTask = Task { @MainActor in
        try await fixture.coordinator.resume()
    }

    try #require(
        await fixture.botService.waitUntilCancellationStarted(timeout: .seconds(1))
    )
    _ = await fixture.botService.waitUntilRequestCount(
        2,
        timeout: .milliseconds(200)
    )
    await fixture.botService.releaseCancellation()
    try await resumeTask.value
    try #require(
        await fixture.botService.waitUntilRequestCount(2, timeout: .seconds(1))
    )

    #expect(await fixture.botService.maximumConcurrentCalls() == 1)

    fixture.coordinator.suspend()
    await fixture.botService.finishAllDecisions()
}
