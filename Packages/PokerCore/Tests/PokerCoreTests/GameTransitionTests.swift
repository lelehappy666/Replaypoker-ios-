import Testing
@testable import PokerCore

@Test func publicTransitionMapsEveryInternalEventInOrderWithoutSeed() throws {
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let cards = try Cards.parse("As Kh Qd")
    let pot = Pot(amount: try Chips(30), eligible: [seat0, seat1])
    let internalEvents: [GameEvent] = [
        .handStarted(seed: 999),
        .blindPosted(seat: seat0, amount: try Chips(10)),
        .holeCardsDealt(seat: seat1),
        .actionApplied(seat: seat1, action: .call),
        .streetChanged(.flop),
        .communityCardsDealt(cards),
        .uncalledBetReturned(seat: seat0, amount: try Chips(10)),
        .potCreated(pot),
        .potAwarded(
            potIndex: 0,
            winners: [seat1],
            amounts: [seat1: try Chips(30)]
        ),
        .handCompleted,
    ]

    #expect(GameTransition(internalEvents).events == [
        .handStarted,
        .blindPosted(seat: seat0, amount: try Chips(10)),
        .holeCardsDealt(seat: seat1),
        .actionApplied(seat: seat1, action: .call),
        .streetChanged(.flop),
        .communityCardsDealt(cards),
        .uncalledBetReturned(seat: seat0, amount: try Chips(10)),
        .potCreated(pot),
        .potAwarded(
            potIndex: 0,
            winners: [seat1],
            amounts: [seat1: try Chips(30)]
        ),
        .handCompleted,
    ])
}
