import Testing
@testable import PokerCore

@Test func 非当前行动玩家离桌弃牌不改变当前行动者() throws {
    let game = try departureGame()
    let before = game.spectatorObservation()
    let actor = try #require(before.currentActor)
    let departing = try #require(
        before.publicSeats.first {
            $0.id != actor && !$0.hasFolded && !$0.isAllIn
        }?.id
    )

    let transition = try game.foldForDeparture(departing)
    let after = game.spectatorObservation()

    #expect(after.currentActor == actor)
    #expect(after.publicSeats.first { $0.id == departing }?.hasFolded == true)
    #expect(
        transition.events.contains(
            .actionApplied(seat: departing, action: .fold)
        )
    )
}

@Test func 当前行动玩家离桌后轮到下一名合法玩家() throws {
    let game = try departureGame()
    let actor = try #require(game.spectatorObservation().currentActor)

    _ = try game.foldForDeparture(actor)
    let after = game.spectatorObservation()

    #expect(after.publicSeats.first { $0.id == actor }?.hasFolded == true)
    #expect(after.currentActor != actor)
    #expect(after.currentActor != nil || after.street == .showdown)
}

@Test func 已弃牌玩家不能重复执行离桌弃牌() throws {
    let game = try departureGame()
    let actor = try #require(game.spectatorObservation().currentActor)
    _ = try game.foldForDeparture(actor)

    #expect(throws: PokerRuleError.self) {
        try game.foldForDeparture(actor)
    }
}

private func departureGame() throws -> HoldemGame {
    let stacks = try Dictionary(uniqueKeysWithValues: (0..<9).map {
        (try SeatID($0), try Chips(4_000))
    })
    return try HoldemGame.start(
        config: HandConfig(
            smallBlind: try Chips(100),
            bigBlind: try Chips(200),
            dealer: try SeatID(0)
        ),
        stacks: stacks,
        seed: 42
    )
}
