import Testing
@testable import PokerCoordinator

@Test @MainActor func 三十秒超时优先过牌且只执行一次() async throws {
    let clock = ManualTableClock()
    let scenario = try await CoordinatorScenario.humanCanCheck(clock: clock)
    #expect(scenario.coordinator.state.secondsRemaining == 30)

    await clock.advance(by: .seconds(30))
    let first = try #require(try scenario.store.humanObservation())
    #expect(first.actions.last?.action == .check)
    let actionCount = first.actions.count

    await clock.advance(by: .seconds(30))
    #expect(try scenario.store.humanObservation()?.actions.count == actionCount)
}

@Test @MainActor func 三十秒超时不能过牌时弃牌() async throws {
    let clock = ManualTableClock()
    let scenario = try await CoordinatorScenario.humanFacingBlind(clock: clock)
    #expect(scenario.coordinator.state.secondsRemaining == 30)

    await clock.advance(by: .seconds(30))

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
