import Testing
@testable import PokerCore

@Test func cardsHaveStableComparableOrder() {
    #expect(Card(rank: .ace, suit: .spades) > Card(rank: .king, suit: .hearts))
    #expect(Set(Card.fullDeck).count == 52)
}

@Test func chipsRejectNegativeAmounts() {
    #expect(throws: PokerRuleError.negativeChips) { try Chips(-1) }
}

@Test func seatIDsRejectValuesOutsideNineSeatTable() {
    #expect(throws: PokerRuleError.invalidSeat) { try SeatID(9) }
}
