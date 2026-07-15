import PokerCore
import PokerSession
import Testing
@testable import PokerCoordinator

@Test @MainActor
func 八个机器人按当前行动者串行执行() async throws {
    let botService = RecordingBotDecisionService()
    let scenario = try await CoordinatorScenario.botOpeningAction(
        botService: botService
    )

    try await scenario.coordinator.runUntilHumanOrSettlement()

    let calls = await botService.requests()
    #expect(!calls.isEmpty)
    #expect(calls.allSatisfy {
        $0.observation.viewer == $0.observation.currentActor
    })
    #expect(calls.allSatisfy { $0.settings == .recommended })
    #expect(calls.allSatisfy { request in
        request.stableIdentity
            == "cash:coordinator-session:seat:\(request.observation.viewer.rawValue)"
    })
    #expect(calls.allSatisfy { $0.seed == 31 })
    #expect(await botService.maximumConcurrentCalls() == 1)
}

@Test @MainActor
func 旧版本机器人结果不会提交() async throws {
    let botService = SuspendedBotDecisionService()
    let scenario = try await CoordinatorScenario.botOpeningAction(
        botService: botService
    )
    await botService.waitUntilRequested()
    let actionCount = try scenario.actionCount()
    let oldVersion = scenario.coordinator.state.stateVersion

    scenario.coordinator.suspend()
    await botService.waitUntilCancelled()
    await botService.resume(with: .fold, stateVersion: oldVersion)
    await Task.yield()

    #expect(scenario.coordinator.state.stateVersion > oldVersion)
    #expect(try scenario.actionCount() == actionCount)
}

@Test @MainActor
func 手牌标识不匹配的机器人结果不会提交() async throws {
    let botService = SuspendedBotDecisionService()
    let scenario = try await CoordinatorScenario.botOpeningAction(
        botService: botService
    )
    await botService.waitUntilRequested()
    let actionCount = try scenario.actionCount()

    await botService.resume(
        with: .fold,
        stateVersion: scenario.coordinator.state.stateVersion,
        handID: "other-hand"
    )
    await Task.yield()

    #expect(try scenario.actionCount() == actionCount)
    scenario.coordinator.suspend()
}

@Test @MainActor
func 行动者已变更时机器人结果不会提交() async throws {
    let botService = SuspendedBotDecisionService()
    let scenario = try await CoordinatorScenario.botOpeningAction(
        botService: botService
    )
    await botService.waitUntilRequested()
    let actor = try #require(scenario.store.cashSession?.currentActor)
    let observation = try #require(try scenario.store.playerObservation(for: actor))
    let legal = try #require(observation.legalActions)
    let action: PlayerAction = legal.canCheck
        ? .check
        : (legal.callAmount != nil ? .call : .fold)
    _ = try scenario.store.apply(action, by: actor)
    let actionCount = try scenario.actionCount()

    await botService.resume(
        with: .fold,
        stateVersion: scenario.coordinator.state.stateVersion
    )
    await Task.yield()

    #expect(try scenario.actionCount() == actionCount)
    scenario.coordinator.suspend()
}

@Test @MainActor
func 服务返回空时仅提交最新合法保底动作() async throws {
    let botService = NilBotDecisionService()
    let scenario = try await CoordinatorScenario.botOpeningAction(
        botService: botService
    )

    try await scenario.coordinator.runUntilHumanOrSettlement()

    let requests = await botService.requests()
    #expect(!requests.isEmpty)
    let actions = try #require(try scenario.store.humanObservation()).actions
    #expect(actions.contains { recorded in
        guard recorded.seat != (try? SeatID(0)) else { return false }
        return recorded.action == .check || recorded.action == .fold
    })
}
