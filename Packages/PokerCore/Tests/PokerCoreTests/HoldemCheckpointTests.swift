import Foundation
import Testing
@testable import PokerCore

@Test func checkpointRoundTripRestoresIdenticalSafeObservationsAndActions() throws {
    let game = try Fixtures.startedNineSeatGame(seed: 77)
    let actor = try #require(game.spectatorObservation().currentActor)
    let playerBefore = try game.playerObservation(for: actor)
    let spectatorBefore = game.spectatorObservation()
    let transitionBefore = game.lastTransition

    let data = try JSONEncoder().encode(game.makeCheckpoint())
    let checkpoint = try JSONDecoder().decode(HoldemCheckpoint.self, from: data)
    let restored = try HoldemGame.restore(from: checkpoint)

    #expect(try restored.playerObservation(for: actor) == playerBefore)
    #expect(restored.spectatorObservation() == spectatorBefore)
    #expect(restored.lastTransition == transitionBefore)
}

@Test func checkpointRoundTripPreservesSubsequentLegalAction() throws {
    let game = try Fixtures.startedNineSeatGame(seed: 78)
    let checkpoint = try JSONDecoder().decode(
        HoldemCheckpoint.self,
        from: JSONEncoder().encode(game.makeCheckpoint())
    )
    let restored = try HoldemGame.restore(from: checkpoint)
    let actor = try #require(game.spectatorObservation().currentActor)
    let action = try #require(try game.playerObservation(for: actor).legalActions?.callAmount)

    #expect(action.rawValue > 0)
    #expect(try restored.apply(.call, by: actor) == game.apply(.call, by: actor))
    #expect(restored.spectatorObservation() == game.spectatorObservation())
}

@Test func checkpointDecodeRejectsDuplicateCard() throws {
    let data = try Fixtures.corruptCheckpointJSON { state in
        var seats = try #require(state["seats"] as? [[String: Any]])
        var firstSeat = try #require(seats.first)
        var secondSeat = seats[1]
        let firstCards = try #require(firstSeat["holeCards"] as? [[String: Any]])
        var secondCards = try #require(secondSeat["holeCards"] as? [[String: Any]])
        secondCards[0] = firstCards[0]
        secondSeat["holeCards"] = secondCards
        seats[1] = secondSeat
        firstSeat["holeCards"] = firstCards
        seats[0] = firstSeat
        state["seats"] = seats
    }

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(HoldemCheckpoint.self, from: data)
    }
}

@Test func checkpointDecodeRejectsBrokenChipConservation() throws {
    let data = try Fixtures.corruptCheckpointJSON { state in
        var seats = try #require(state["seats"] as? [[String: Any]])
        var firstSeat = try #require(seats.first)
        let stack = try #require(firstSeat["stack"] as? Int)
        firstSeat["stack"] = stack + 1
        seats[0] = firstSeat
        state["seats"] = seats
    }

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(HoldemCheckpoint.self, from: data)
    }
}

@Test func checkpointDecodeRejectsMissingCurrentActor() throws {
    let data = try Fixtures.corruptCheckpointJSON { state in
        state["currentActor"] = NSNull()
    }

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(HoldemCheckpoint.self, from: data)
    }
}

private extension Fixtures {
    static func startedNineSeatGame(seed: UInt64) throws -> HoldemGame {
        try HoldemGame.start(
            config: standardConfig(dealer: 0),
            stacks: nineStacks(10_000),
            seed: seed
        )
    }

    static func corruptCheckpointJSON(
        _ mutation: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        let game = try startedNineSeatGame(seed: 79)
        let validData = try JSONEncoder().encode(game.makeCheckpoint())
        var checkpoint = try #require(
            JSONSerialization.jsonObject(with: validData) as? [String: Any]
        )
        var state = try #require(checkpoint["state"] as? [String: Any])
        try mutation(&state)
        checkpoint["state"] = state
        return try JSONSerialization.data(withJSONObject: checkpoint, options: [.sortedKeys])
    }
}
