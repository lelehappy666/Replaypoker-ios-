import PokerCore
import Testing
@testable import PokerBot

@Test func 新状态会丢弃仍在计算的旧版本结果() async throws {
    let service = BotDecisionService(
        decisionMaker: VersionedDecisionMaker(),
        timeout: .seconds(1),
        appliesDisplayDelay: false
    )
    let oldRequest = try makeDecisionRequest(version: 1)
    let newRequest = try makeDecisionRequest(version: 2)

    let oldTask = Task { await service.decide(oldRequest) }
    try await Task.sleep(for: .milliseconds(2))
    let newResult = await service.decide(newRequest)
    let oldResult = await oldTask.value

    #expect(oldResult == nil)
    #expect(newResult?.stateVersion == 2)
}

@Test func 显式取消不会返回可提交动作() async throws {
    let service = BotDecisionService(
        decisionMaker: SlowDecisionMaker(delay: .milliseconds(100)),
        timeout: .seconds(1),
        appliesDisplayDelay: false
    )
    let request = try makeDecisionRequest()
    let task = Task { await service.decide(request) }
    try await Task.sleep(for: .milliseconds(2))

    await service.cancel(handID: request.observation.handID)

    #expect(await task.value == nil)
}

@Test func 超时和引擎错误选择安全保底动作() async throws {
    let checkRequest = try makeDecisionRequest(
        legalActions: #"{"canFold":false,"canCheck":true,"callAmount":null,"minimumBet":null,"minimumRaiseTo":null,"maximumRaiseTo":null,"canAllIn":false}"#
    )
    let timeoutService = BotDecisionService(
        decisionMaker: SlowDecisionMaker(delay: .milliseconds(100)),
        timeout: .milliseconds(5),
        appliesDisplayDelay: false
    )
    let timeoutResult = await timeoutService.decide(checkRequest)
    #expect(timeoutResult?.action == .check)
    #expect(timeoutResult?.reason == .fallbackTimeout)

    let foldRequest = try makeDecisionRequest()
    let errorService = BotDecisionService(
        decisionMaker: FailingDecisionMaker(),
        timeout: .seconds(1),
        appliesDisplayDelay: false
    )
    let errorResult = await errorService.decide(foldRequest)
    #expect(errorResult?.action == .fold)
    #expect(errorResult?.reason == .fallbackError)
}

@Test func 展示思考延迟按种子稳定且位于对应区间() {
    let ranges: [(BotThinkingSpeed, ClosedRange<Int>)] = [
        (.fast, 200...500),
        (.standard, 600...1_200),
        (.natural, 1_200...2_500),
    ]
    for (speed, range) in ranges {
        for seed in 0..<100 {
            let first = BotDecisionService.displayDelayMilliseconds(
                speed: speed,
                seed: UInt64(seed)
            )
            let second = BotDecisionService.displayDelayMilliseconds(
                speed: speed,
                seed: UInt64(seed)
            )
            #expect(range.contains(first))
            #expect(first == second)
        }
    }
}

@Test func 并发请求压力下每手只保留最新状态() async throws {
    let service = BotDecisionService(
        decisionMaker: VersionedDecisionMaker(),
        timeout: .seconds(1),
        appliesDisplayDelay: false
    )
    await withTaskGroup(of: BotDecision?.self) { group in
        for version in 0..<100 {
            group.addTask {
                guard let request = try? makeDecisionRequest(version: version) else {
                    return nil
                }
                return await service.decide(request)
            }
        }
        var results: [BotDecision] = []
        for await result in group {
            if let result { results.append(result) }
        }
        #expect(results.allSatisfy { $0.stateVersion == 99 })
        #expect(results.count <= 1)
    }
}

private struct SlowDecisionMaker: BotDecisionMaking {
    let delay: Duration

    func decide(_ request: BotDecisionRequest) async throws -> BotDecision {
        try await Task.sleep(for: delay)
        return decision(for: request)
    }
}

private struct VersionedDecisionMaker: BotDecisionMaking {
    func decide(_ request: BotDecisionRequest) async throws -> BotDecision {
        let delay: Duration = request.observation.stateVersion == 99
            ? .milliseconds(1)
            : .milliseconds(50)
        try await Task.sleep(for: delay)
        return decision(for: request)
    }
}

private struct FailingDecisionMaker: BotDecisionMaking {
    func decide(_ request: BotDecisionRequest) async throws -> BotDecision {
        throw BotError.invalidObservation
    }
}

private func decision(for request: BotDecisionRequest) -> BotDecision {
    BotDecision(
        action: .fold,
        handID: request.observation.handID,
        stateVersion: request.observation.stateVersion,
        reason: .ruleEvaluation,
        simulationIterations: 0
    )
}

private func makeDecisionRequest(
    version: Int = 1,
    legalActions: String = #"{"canFold":true,"canCheck":false,"callAmount":100,"minimumBet":null,"minimumRaiseTo":400,"maximumRaiseTo":1000,"canAllIn":true}"#
) throws -> BotDecisionRequest {
    BotDecisionRequest(
        observation: try makeSimulationObservation(
            legalActions: legalActions,
            stateVersion: version
        ),
        settings: try decisionSettings(),
        stableIdentity: "服务机器人",
        seed: UInt64(version),
        history: nil
    )
}
