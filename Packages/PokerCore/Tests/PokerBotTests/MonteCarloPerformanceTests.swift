import Foundation
import Testing
@testable import PokerBot

@Test func 三档既定模拟次数完成并记录耗时() async throws {
    let observation = try makeSimulationObservation()
    let estimator = MonteCarloEstimator()
    let clock = ContinuousClock()

    for iterations in [800, 2_000, 5_000] {
        let start = clock.now
        let result = try await estimator.estimate(
            observation,
            iterations: iterations,
            seed: UInt64(iterations)
        )
        let elapsed = start.duration(to: clock.now)
        print("机器人权益模拟 \(iterations) 次耗时：\(elapsed)")
        #expect(result.iterations == iterations)
        #expect((0...10_000).contains(result.effectiveBasisPoints))
        #expect(elapsed < .seconds(60))
    }
}
