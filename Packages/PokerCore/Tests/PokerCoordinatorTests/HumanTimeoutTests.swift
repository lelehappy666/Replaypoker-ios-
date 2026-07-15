import Testing
@testable import PokerCoordinator

@Test @MainActor func 三十秒超时优先过牌且只执行一次() async throws {
    let clock = ManualTableClock()
    let scenario = try await CoordinatorScenario.humanCanCheck(clock: clock)
    #expect(scenario.coordinator.state.secondsRemaining == 30)
    let initialActionCount = try #require(
        try scenario.store.humanObservation()
    ).actions.count

    await advanceScheduledTicks(30, clock: clock)
    while try scenario.store.humanObservation()?.actions.count == initialActionCount {
        await Task.yield()
    }
    let first = try #require(try scenario.store.humanObservation())
    #expect(first.actions.last?.action == .check)
    let actionCount = first.actions.count

    await clock.advance(by: .seconds(30))
    #expect(try scenario.store.humanObservation()?.actions.count == actionCount)
}

@Test @MainActor func 倒计时每秒更新剩余时间() async throws {
    let clock = ManualTableClock()
    let scenario = try await CoordinatorScenario.humanCanCheck(clock: clock)

    #expect(scenario.coordinator.state.secondsRemaining == 30)
    await advanceScheduledTicks(1, clock: clock)
    while scenario.coordinator.state.secondsRemaining != 29 { await Task.yield() }
    #expect(scenario.coordinator.state.secondsRemaining == 29)
    await advanceScheduledTicks(1, clock: clock)
    while scenario.coordinator.state.secondsRemaining != 28 { await Task.yield() }
    #expect(scenario.coordinator.state.secondsRemaining == 28)
}

@Test @MainActor func 单步唤醒后暂停不会让后续推进阻塞() async throws {
    let clock = ManualTableClock()
    let scenario = try await CoordinatorScenario.humanCanCheck(clock: clock)
    let actionCount = try #require(try scenario.store.humanObservation()).actions.count

    await clock.advanceOneSecond()
    while scenario.coordinator.state.secondsRemaining != 29 { await Task.yield() }
    scenario.coordinator.suspend()
    await clock.waitUntilIdle()
    await clock.advance(by: .seconds(29))

    #expect(scenario.coordinator.state.phase == .suspended)
    #expect(try scenario.store.humanObservation()?.actions.count == actionCount)
    #expect(await clock.waiterCount() == 0)
}

@Test @MainActor func 三十秒超时不能过牌时弃牌() async throws {
    let clock = ManualTableClock()
    let scenario = try await CoordinatorScenario.humanFacingBlind(clock: clock)
    #expect(scenario.coordinator.state.secondsRemaining == 30)
    let initialActionCount = try #require(
        try scenario.store.humanObservation()
    ).actions.count

    await advanceScheduledTicks(30, clock: clock)
    while try scenario.store.humanObservation()?.actions.count == initialActionCount {
        await Task.yield()
    }

    #expect(try scenario.store.humanObservation()?.actions.last?.action == .fold)
}

@Test @MainActor func 成功动作取消旧倒计时() async throws {
    let clock = ManualTableClock()
    let scenario = try await CoordinatorScenario.humanFacingBlind(clock: clock)

    try await scenario.coordinator.send(.fold)
    let actionCount = try #require(try scenario.store.humanObservation()).actions.count
    await clock.advance(by: .seconds(30))

    #expect(try scenario.store.humanObservation()?.actions.count == actionCount)
}

@Test @MainActor func 暂停取消倒计时并拒绝后续操作() async throws {
    let clock = ManualTableClock()
    let scenario = try await CoordinatorScenario.humanFacingBlind(clock: clock)
    let actionCount = try #require(try scenario.store.humanObservation()).actions.count

    scenario.coordinator.suspend()
    await clock.advance(by: .seconds(30))

    #expect(scenario.coordinator.state.phase == .suspended)
    #expect(try scenario.store.humanObservation()?.actions.count == actionCount)
    await #expect(throws: PokerCoordinatorError.suspended) {
        try await scenario.coordinator.send(.fold)
    }
}

@Test @MainActor func 释放协调器会立即取消倒计时且不再操作() async throws {
    let clock = ManualTableClock()
    var scenario: CoordinatorScenario? = try await .humanFacingBlind(clock: clock)
    let store = try #require(scenario?.store)
    let actionCount = try #require(try store.humanObservation()).actions.count
    weak let coordinator = scenario?.coordinator

    scenario = nil

    #expect(coordinator == nil)
    await clock.advance(by: .seconds(30))
    #expect(try store.humanObservation()?.actions.count == actionCount)
    #expect(await clock.waiterCount() == 0)
}

@Test @MainActor func 动作展示等待中暂停不会被旧操作覆盖() async throws {
    let clock = ManualTableClock()
    let animationGate = ManualAnimationGate()
    let scenario = try await CoordinatorScenario.humanFacingBlind(
        clock: clock,
        animationGate: animationGate
    )
    await animationGate.enable()
    let coordinator = scenario.coordinator
    let sendTask = Task { @MainActor in
        try await coordinator.send(.fold)
    }
    await animationGate.waitUntilBlocked()

    coordinator.suspend()
    await animationGate.resume()
    try await sendTask.value

    #expect(coordinator.state.phase == .suspended)
    #expect(coordinator.state.secondsRemaining == nil)
    #expect(await clock.waiterCount() == 0)
    await #expect(throws: PokerCoordinatorError.suspended) {
        try await coordinator.send(.fold)
    }
}

@Test @MainActor func 发牌展示等待中暂停不会被开局流程覆盖() async throws {
    let clock = ManualTableClock()
    let animationGate = ManualAnimationGate()
    let scenario = try CoordinatorScenario.readyToStartWithHumanFirst(
        clock: clock,
        animationGate: animationGate
    )
    await animationGate.enable()
    let coordinator = scenario.coordinator
    let startTask = Task { @MainActor in
        try await coordinator.startHand(settings: .recommended)
    }
    await animationGate.waitUntilBlocked()

    coordinator.suspend()
    await animationGate.resume()
    try await startTask.value

    #expect(coordinator.state.phase == .suspended)
    #expect(coordinator.state.secondsRemaining == nil)
    #expect(await clock.waiterCount() == 0)
}

@Test func 取消发生在登记边界时不会成功唤醒() async {
    let clock = ManualTableClock(advanceImmediatelyOnRegistration: true) { _ in
        withUnsafeCurrentTask { $0?.cancel() }
    }

    let result = await Task {
        try await clock.sleep(for: .seconds(1))
    }.result

    #expect(throws: CancellationError.self) {
        try result.get()
    }
    await clock.advance(by: .seconds(30))
    #expect(await clock.waiterCount() == 0)
}

private func advanceScheduledTicks(
    _ count: Int,
    clock: ManualTableClock
) async {
    for _ in 0..<count {
        await clock.waitUntilScheduled()
        await clock.advanceOneSecond()
    }
}
