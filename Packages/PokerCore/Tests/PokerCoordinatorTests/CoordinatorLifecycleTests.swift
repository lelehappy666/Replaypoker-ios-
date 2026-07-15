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

@Test @MainActor
func 取消服务返回后仍等待旧机器人任务完整退出() async throws {
    let fixture = try await CoordinatorScenario.botThinking(
        delayFirstDecisionExitAfterCancellation: true
    )
    fixture.coordinator.suspend()
    let resumeTask = Task { @MainActor in
        try await fixture.coordinator.resume()
    }

    try #require(
        await fixture.botService.waitUntilDecisionExitBlocked(timeout: .seconds(1))
    )
    let newRequestStarted = await fixture.botService.waitUntilRequestCount(
        2,
        timeout: .milliseconds(200)
    )
    #expect(newRequestStarted == false)
    #expect(await fixture.botService.currentRequestCount() == 1)

    await fixture.botService.releaseDecisionExit()
    try await resumeTask.value
    try #require(
        await fixture.botService.waitUntilRequestCount(2, timeout: .seconds(1))
    )
    #expect(await fixture.botService.maximumConcurrentCalls() == 1)

    fixture.coordinator.suspend()
    await fixture.botService.finishAllDecisions()
}

@Test @MainActor
func 等待下一手与保存失败阶段不会被生命周期暂停改写() async throws {
    let ready = try CoordinatorScenario.readyToStartWithHumanFirst()
    ready.coordinator.suspend()
    #expect(ready.coordinator.state.phase == .awaitingNextHand)

    let failed = try await CoordinatorScenario.pendingSettlement(
        repository: FailOnceSessionRepository()
    )
    await failed.coordinator.finishSettlement()
    #expect(failed.coordinator.state.phase == .saveFailed)
    failed.coordinator.suspend()
    #expect(failed.coordinator.state.phase == .saveFailed)
}
