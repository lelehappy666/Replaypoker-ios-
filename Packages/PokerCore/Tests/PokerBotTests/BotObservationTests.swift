import Foundation
import Testing
import PokerBot
import PokerCore

@Test func 安全观察只复制玩家公开信息并计算底池() throws {
    let source = try makePlayerObservation(hasLegalActions: true)
    let observation = try BotObservation(
        handID: "hand-1",
        stateVersion: 7,
        observation: source
    )

    #expect(observation.handID == "hand-1")
    #expect(observation.stateVersion == 7)
    #expect(observation.viewer == source.viewer)
    #expect(observation.ownHoleCards == source.ownHoleCards)
    #expect(observation.communityCards == source.communityCards)
    #expect(observation.publicSeats == source.publicSeats)
    #expect(observation.pot.rawValue == 300)
    #expect(observation.legalActions == source.legalActions)
}

@Test func 安全观察拒绝空标识负版本和非当前行动玩家() throws {
    let acting = try makePlayerObservation(hasLegalActions: true)
    let waiting = try makePlayerObservation(hasLegalActions: false)

    #expect(throws: BotError.invalidObservation) {
        try BotObservation(handID: " ", stateVersion: 0, observation: acting)
    }
    #expect(throws: BotError.invalidObservation) {
        try BotObservation(handID: "hand-1", stateVersion: -1, observation: acting)
    }
    #expect(throws: BotError.invalidObservation) {
        try BotObservation(handID: "hand-1", stateVersion: 0, observation: waiting)
    }
}

private func makePlayerObservation(hasLegalActions: Bool) throws -> PlayerObservation {
    let legalActions = hasLegalActions
        ? #", "legalActions":{"canFold":true,"canCheck":false,"callAmount":100,"minimumBet":null,"minimumRaiseTo":400,"maximumRaiseTo":1000,"canAllIn":true}"#
        : #", "legalActions":null"#
    let currentActor = hasLegalActions ? "0" : "1"
    let json = """
    {
        "viewer":0,
        "ownHoleCards":[{"rank":14,"suit":3},{"rank":13,"suit":3}],
        "communityCards":[{"rank":2,"suit":0},{"rank":7,"suit":1},{"rank":10,"suit":2}],
        "publicSeats":[
            {"id":0,"stack":900,"committedThisStreet":100,"committedThisHand":100,"hasFolded":false,"isAllIn":false,"isSittingOut":false},
            {"id":1,"stack":800,"committedThisStreet":200,"committedThisHand":200,"hasFolded":false,"isAllIn":false,"isSittingOut":false}
        ],
        "currentActor":\(currentActor),
        "street":1,
        "currentBet":200\(legalActions),
        "actions":[]
    }
    """
    return try JSONDecoder().decode(PlayerObservation.self, from: Data(json.utf8))
}
