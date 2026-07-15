import PokerBot
import PokerCore
import PokerSession
import Testing
@testable import PokerCoordinator

@Test @MainActor func 保存失败停留结算且相同业务编号重试() async throws {
    let repository = FailOnceSessionRepository()
    let businessIDs = BusinessIDSequence()
    let scenario = try await CoordinatorScenario.pendingSettlement(
        repository: repository,
        businessIDs: businessIDs
    )

    await scenario.coordinator.finishSettlement()

    #expect(scenario.coordinator.state.phase == .saveFailed)
    #expect(scenario.coordinator.state.errorMessage == "牌局保存失败，请重试。")
    let firstID = try #require(repository.attemptedBusinessIDs().first)

    try await scenario.coordinator.retrySave()

    #expect(scenario.coordinator.state.phase == .awaitingNextHand)
    #expect(repository.attemptedBusinessIDs() == [firstID, firstID])
    #expect(businessIDs.values() == [firstID])
}

@Test @MainActor func 真实行动链结束后自动摊牌并保存() async throws {
    let repository = FailOnceSessionRepository(failSettlementOnce: false)
    let scenario = try await CoordinatorScenario.automaticSettlement(
        repository: repository
    )
    try await scenario.playDeterministicallyToSettlement()
    await scenario.waitForAutomaticSettlement()

    #expect(scenario.coordinator.state.phase == .awaitingNextHand)
    #expect(scenario.store.cashSession?.phase == .readyForHand)
    #expect(scenario.store.handRecords().count == 1)
}

@Test @MainActor func 真实行动链自动保存失败后可用同一编号重试() async throws {
    let repository = FailOnceSessionRepository()
    let businessIDs = BusinessIDSequence()
    let scenario = try await CoordinatorScenario.automaticSettlement(
        repository: repository,
        businessIDs: businessIDs
    )
    try await scenario.playDeterministicallyToSettlement()
    await scenario.waitForAutomaticSettlement()

    #expect(scenario.coordinator.state.phase == .saveFailed)
    let firstID = try #require(repository.attemptedBusinessIDs().first)
    try await scenario.coordinator.retrySave()
    #expect(scenario.coordinator.state.phase == .awaitingNextHand)
    #expect(repository.attemptedBusinessIDs() == [firstID, firstID])
    #expect(businessIDs.values() == [firstID])
}

@Test @MainActor func 摊牌只亮出安全观察中的未弃牌座位() async throws {
    let repository = FailOnceSessionRepository(failSettlementOnce: false)
    let scenario = try await CoordinatorScenario.pendingSettlement(repository: repository)
    let showdown = try #require(scenario.store.pendingShowdownObservation)

    await scenario.coordinator.finishSettlement()

    for seat in scenario.coordinator.state.seats {
        if let cards = showdown.cardsBySeat[seat.id] {
            #expect(seat.cards == cards.map(TableCardState.faceUp))
        } else if seat.hasFolded {
            #expect(seat.cards == [.faceDown, .faceDown])
        }
    }
    #expect(scenario.coordinator.state.phase == .awaitingNextHand)
}

@Test @MainActor func 未弃牌但安全观察无牌面时仍显示两张牌背() async throws {
    let scenario = try await CoordinatorScenario.pendingSettlementWithoutRanks()
    let showdown = try #require(scenario.store.pendingShowdownObservation)
    #expect(showdown.cardsBySeat.isEmpty)

    await scenario.coordinator.finishSettlement()

    let remaining = try #require(
        scenario.coordinator.state.seats.first { !$0.hasFolded }
    )
    #expect(remaining.cards == [.faceDown, .faceDown])
}

@Test @MainActor func 业务编号生成失败不会进入可重试保存态() async throws {
    let repository = FailOnceSessionRepository(failSettlementOnce: false)
    let scenario = try await CoordinatorScenario.pendingSettlement(
        repository: repository,
        failBusinessIDGeneration: true
    )

    await scenario.coordinator.finishSettlement()

    #expect(scenario.coordinator.state.phase != .saveFailed)
    #expect(scenario.coordinator.state.errorMessage == "无法创建牌局保存编号。")
    await #expect(throws: PokerCoordinatorError.invalidPhase) {
        try await scenario.coordinator.retrySave()
    }
    #expect(repository.attemptedBusinessIDs().isEmpty)
}

@Test @MainActor func 仅保存失败可重试且仅等待时可开下一手() async throws {
    let repository = FailOnceSessionRepository()
    let scenario = try await CoordinatorScenario.pendingSettlement(repository: repository)

    await scenario.coordinator.finishSettlement()
    await #expect(throws: PokerCoordinatorError.invalidPhase) {
        try await scenario.coordinator.startNextHand(settings: .recommended)
    }
    try await scenario.coordinator.retrySave()
    await #expect(throws: PokerCoordinatorError.invalidPhase) {
        try await scenario.coordinator.retrySave()
    }

    let nextSettings = try BotSettings(
        difficulty: .hard,
        model: .aggressive,
        aggression: 80,
        bluffFrequency: 45,
        callingWidth: 60,
        betSizing: 70,
        thinkingSpeed: .fast,
        analyzesHistory: false
    )
    try await scenario.coordinator.startNextHand(settings: nextSettings)
    #expect(scenario.coordinator.frozenSettings == nextSettings)
}
