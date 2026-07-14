import Foundation
import Testing
@testable import PokerCore

@Test func cardsHaveStableComparableOrder() {
    #expect(Card(rank: .ace, suit: .spades) > Card(rank: .king, suit: .hearts))
}

@Test func cardsWithSameRankHaveStableSuitOrder() {
    #expect(Card(rank: .ace, suit: .spades) > Card(rank: .ace, suit: .hearts))
}

@Test func fullDeckContainsExactlyFiftyTwoUniqueCards() {
    #expect(Card.fullDeck.count == 52)
    #expect(Set(Card.fullDeck).count == 52)
}

@Test func chipsRejectNegativeAmounts() {
    #expect(throws: PokerRuleError.negativeChips) { try Chips(-1) }
    #expect(Chips(rawValue: -1) == nil)
}

@Test func seatIDsRejectValuesOutsideNineSeatTable() {
    #expect(throws: PokerRuleError.invalidSeat) { try SeatID(9) }
    #expect(SeatID(rawValue: -1) == nil)
    #expect(SeatID(rawValue: 9) == nil)
}

@Test func chipsRejectInvalidJSONAndUseSingleIntegerEncoding() throws {
    do {
        _ = try JSONDecoder().decode(Chips.self, from: Data("-1".utf8))
        Issue.record("Expected negative chips JSON to fail decoding")
    } catch let DecodingError.dataCorrupted(context) {
        #expect(context.debugDescription == "Invalid Chips value: -1")
    } catch {
        Issue.record("Expected dataCorrupted, got \(error)")
    }

    let encoded = try JSONEncoder().encode(try Chips(42))
    #expect(String(decoding: encoded, as: UTF8.self) == "42")
}

@Test func seatIDsRejectInvalidJSONAndUseSingleIntegerEncoding() throws {
    for value in [-1, 9] {
        do {
            _ = try JSONDecoder().decode(SeatID.self, from: Data("\(value)".utf8))
            Issue.record("Expected invalid seat JSON \(value) to fail decoding")
        } catch let DecodingError.dataCorrupted(context) {
            #expect(context.debugDescription == "Invalid SeatID value: \(value)")
        } catch {
            Issue.record("Expected dataCorrupted for \(value), got \(error)")
        }
    }

    let encoded = try JSONEncoder().encode(try SeatID(8))
    #expect(String(decoding: encoded, as: UTF8.self) == "8")
}

@Test func cardsParseSupportedRankAndSuitBoundaries() throws {
    #expect(try Cards.parse("2c Td Kh As") == [
        Card(rank: .two, suit: .clubs),
        Card(rank: .ten, suit: .diamonds),
        Card(rank: .king, suit: .hearts),
        Card(rank: .ace, suit: .spades),
    ])
}

@Test func cardsRejectInvalidLengthRankAndSuit() {
    #expect(throws: PokerRuleError.invalidCards) { try Cards.parse("10s") }
    #expect(throws: PokerRuleError.invalidCards) { try Cards.parse("Xs") }
    #expect(throws: PokerRuleError.invalidCards) { try Cards.parse("Ax") }
}
