import PokerCore
import Testing
@testable import PokerCoordinator

@Test @MainActor func 真人意图只映射到最新合法动作() async throws {
    let scenario = try await CoordinatorScenario.humanFacingRaise()
    let coordinator = scenario.coordinator
    let legal = try #require(try scenario.store.humanObservation()?.legalActions)
    let minimum = try #require(legal.minimumRaiseTo)
    let maximum = try #require(legal.maximumRaiseTo)

    await #expect(throws: PokerCoordinatorError.illegalIntent) {
        try await coordinator.send(.aggressive(amount: Chips(rawValue: minimum.rawValue - 1)!))
    }
    await #expect(throws: PokerCoordinatorError.illegalIntent) {
        try await coordinator.send(.aggressive(amount: try Chips(maximum.rawValue + 1)))
    }
    let version = coordinator.state.stateVersion
    try await coordinator.send(.aggressive(amount: minimum))

    #expect(coordinator.state.stateVersion > version)
    #expect(try scenario.store.humanObservation()?.actions.last?.action == .raiseTo(minimum))
}

@Test @MainActor func 最大下注映射为全下而不是越界加注() async throws {
    let scenario = try await CoordinatorScenario.humanCanRaiseToAllIn()
    let coordinator = scenario.coordinator
    let legal = try #require(try scenario.store.humanObservation()?.legalActions)
    let maximum = try #require(legal.maximumRaiseTo)

    try await coordinator.send(.aggressive(amount: maximum))

    #expect(try scenario.store.humanObservation()?.actions.last?.action == .allIn)
}

@Test @MainActor func 中间操作面对下注时映射为跟注() async throws {
    let scenario = try await CoordinatorScenario.humanFacingBlind()

    try await scenario.coordinator.send(.middle)

    #expect(try scenario.store.humanObservation()?.actions.last?.action == .call)
}

@Test @MainActor func 中间操作无需跟注时映射为过牌() async throws {
    let scenario = try await CoordinatorScenario.humanCanCheck()

    try await scenario.coordinator.send(.middle)

    #expect(try scenario.store.humanObservation()?.actions.last?.action == .check)
}

@Test @MainActor func 无人下注时激进操作映射为下注() async throws {
    let scenario = try await CoordinatorScenario.humanCanBet()
    let legal = try #require(try scenario.store.humanObservation()?.legalActions)
    let minimum = try #require(legal.minimumBet)

    try await scenario.coordinator.send(.aggressive(amount: minimum))

    #expect(try scenario.store.humanObservation()?.actions.last?.action == .bet(minimum))
}

@Test @MainActor func 面对下注时可以弃牌() async throws {
    let scenario = try await CoordinatorScenario.humanFacingBlind()

    try await scenario.coordinator.send(.fold)

    #expect(try scenario.store.humanObservation()?.actions.last?.action == .fold)
}
