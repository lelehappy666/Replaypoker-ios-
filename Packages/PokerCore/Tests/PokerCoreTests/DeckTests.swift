import Foundation
import Testing
@testable import PokerCore

@Test(arguments: [-1, 53])
func decodingRejectsOutOfRangeDeckIndex(_ nextIndex: Int) throws {
    let deck = Deck.shuffled(seed: 99)
    let encoded = try JSONEncoder().encode(deck)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["nextIndex"] = nextIndex
    let damaged = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Deck.self, from: damaged)
    }
}

@Test func decodingRejectsDeckWithDuplicateCard() throws {
    let deck = Deck.shuffled(seed: 100)
    let encoded = try JSONEncoder().encode(deck)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var cards = try #require(object["cards"] as? [[String: Any]])
    cards[1] = cards[0]
    object["cards"] = cards
    let damaged = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Deck.self, from: damaged)
    }
}

@Test(arguments: [0, 51])
func decodingRejectsDeckWithoutExactlyFiftyTwoCards(_ keptCount: Int) throws {
    let encoded = try JSONEncoder().encode(Deck.shuffled(seed: 101))
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let cards = try #require(object["cards"] as? [[String: Any]])
    object["cards"] = Array(cards.prefix(keptCount))
    object["nextIndex"] = 0
    let damaged = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Deck.self, from: damaged)
    }
}

@Test func decodingRejectsDeckWithFiftyThreeCards() throws {
    let encoded = try JSONEncoder().encode(Deck.shuffled(seed: 102))
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var cards = try #require(object["cards"] as? [[String: Any]])
    cards.append(cards[0])
    object["cards"] = cards
    let damaged = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Deck.self, from: damaged)
    }
}

@Test func decodingRejectsDeckWithIllegalCardValue() throws {
    let encoded = try JSONEncoder().encode(Deck.shuffled(seed: 103))
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var cards = try #require(object["cards"] as? [[String: Any]])
    cards[0]["suit"] = 99
    object["cards"] = cards
    let damaged = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Deck.self, from: damaged)
    }
}

@Test func drawDefensivelyRejectsNegativeInternalPosition() throws {
    var deck = Deck(cards: Card.fullDeck, nextIndex: -1)

    #expect(throws: PokerRuleError.invalidState("invalid deck position")) {
        try deck.draw()
    }
}

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
