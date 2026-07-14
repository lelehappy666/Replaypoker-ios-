import Foundation
import Testing
@testable import PokerCore

@Test func equalSeedsProduceEqualDecks() throws {
    var first = Deck.shuffled(seed: 42)
    var second = Deck.shuffled(seed: 42)

    #expect(try (0..<52).map { _ in try first.draw() } == (0..<52).map { _ in try second.draw() })
}

@Test func differentSeedsProduceDifferentDecks() throws {
    var first = Deck.shuffled(seed: 42)
    var second = Deck.shuffled(seed: 43)

    #expect(try (0..<52).map { _ in try first.draw() } != (0..<52).map { _ in try second.draw() })
}

@Test func drawingWholeDeckProducesEveryCardExactlyOnce() throws {
    var deck = Deck.shuffled(seed: 7)
    let cards = try (0..<52).map { _ in try deck.draw() }

    #expect(Set(cards).count == 52)
    #expect(throws: PokerRuleError.deckExhausted) { try deck.draw() }
}

@Test func remainingCardsTracksDrawPosition() throws {
    var deck = Deck.shuffled(seed: 17)
    let firstCard = try deck.draw()

    #expect(deck.remainingCards.count == 51)
    #expect(!deck.remainingCards.contains(firstCard))
}

@Test func encodedDeckResumesAtSamePosition() throws {
    var deck = Deck.shuffled(seed: 99)
    _ = try deck.draw()
    let restored = try JSONDecoder().decode(Deck.self, from: JSONEncoder().encode(deck))
    var lhs = deck
    var rhs = restored

    #expect(try lhs.draw() == rhs.draw())
}
