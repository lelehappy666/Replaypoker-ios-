import Foundation
import PokerCore
import Testing
@testable import PokerBot

@Test func 九人桌三档既定模拟次数完成并记录耗时() async throws {
    let observation = try makeNineSeatSimulationObservation()
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
        #expect(elapsed < .seconds(15))
    }
}

private func makeNineSeatSimulationObservation() throws -> BotObservation {
    let publicSeats = (0..<9).map { seat in
        """
        {"id":\(seat),"stack":900,"committedThisStreet":100,"committedThisHand":100,"hasFolded":false,"isAllIn":false,"isSittingOut":false}
        """
    }.joined(separator: ",")
    let json = """
    {
        "viewer":0,
        "ownHoleCards":[{"rank":14,"suit":3},{"rank":13,"suit":2}],
        "communityCards":[{"rank":2,"suit":0},{"rank":7,"suit":1},{"rank":10,"suit":2}],
        "publicSeats":[\(publicSeats)],
        "currentActor":0,
        "street":1,
        "currentBet":100,
        "legalActions":{"canFold":false,"canCheck":true,"callAmount":null,"minimumBet":100,"minimumRaiseTo":null,"maximumRaiseTo":900,"canAllIn":true},
        "actions":[]
    }
    """
    let player = try JSONDecoder().decode(
        PlayerObservation.self,
        from: Data(json.utf8)
    )
    return try BotObservation(
        handID: "nine-seat-performance",
        stateVersion: 1,
        config: HandConfig(
            smallBlind: Chips(rawValue: 50)!,
            bigBlind: Chips(rawValue: 100)!,
            dealer: SeatID(rawValue: 1)!
        ),
        observation: player
    )
}
