import PokerBot
import PokerCore
import PokerSession
import Testing
@testable import PokerCoordinator

@Test @MainActor
func 二百手确定性机器人串行且筹码守恒() async throws {
    var firstRun: [[Int]] = []
    var secondRun: [[Int]] = []

    for repetition in 0..<2 {
        for seed in 0..<100 {
            let botService = RecordingBotDecisionService()
            let scenario = try await CoordinatorScenario.botOpeningAction(
                botService: botService,
                seed: UInt64(seed)
            )

            try await scenario.playDeterministicallyToSettlement()

            #expect(scenario.store.cashSession?.phase == .settlementPending)
            let showdown = try #require(scenario.store.pendingShowdownObservation)
            #expect(showdown.cardsBySeat.values.allSatisfy { $0.count == 2 })
            let spectator = try #require(scenario.store.spectatorObservation)
            #expect(spectator.street == .complete)
            let requests = await botService.requests()
            let botActions = await botService.actions()
            #expect(requests.count == botActions.count)
            #expect(zip(requests, botActions).allSatisfy { request, action in
                legal(request.observation.legalActions, contains: action)
            })
            #expect(spectator.actions.allSatisfy { action in
                actionWasLegal(action, in: requests)
                    || action.seat == (try? SeatID(0))
            })
            #expect(
                spectator.actions.filter { $0.seat != (try? SeatID(0)) }.count
                    == botActions.count
            )
            #expect(await botService.maximumConcurrentCalls() == 1)

            let finalStacks = spectator.publicSeats
                .sorted { $0.id < $1.id }
                .map(\.stack.rawValue)
            #expect(finalStacks.reduce(0, +) == 36_000)
            if repetition == 0 {
                firstRun.append(finalStacks)
            } else {
                secondRun.append(finalStacks)
            }
        }
    }

    #expect(firstRun == secondRun)
}

private func actionWasLegal(
    _ recorded: RecordedAction,
    in requests: [BotDecisionRequest]
) -> Bool {
    requests.contains { request in
        request.observation.viewer == recorded.seat
            && request.observation.street == recorded.street
            && legal(request.observation.legalActions, contains: recorded.action)
    }
}

private func legal(_ legal: LegalActionSet, contains action: PlayerAction) -> Bool {
    switch action {
    case .fold: legal.canFold
    case .check: legal.canCheck
    case .call: legal.callAmount != nil
    case let .bet(amount):
        legal.minimumBet.map { amount >= $0 } == true
            && legal.maximumRaiseTo.map { amount <= $0 } == true
    case let .raiseTo(amount):
        legal.minimumRaiseTo.map { amount >= $0 } == true
            && legal.maximumRaiseTo.map { amount <= $0 } == true
    case .allIn: legal.canAllIn
    }
}
