public struct Deck: Codable, Equatable, Sendable {
    private var cards: [Card]
    private var nextIndex: Int

    public static func shuffled(seed: UInt64) -> Self {
        var cards = Card.fullDeck
        var generator = SeededGenerator(seed: seed)
        cards.shuffle(using: &generator)
        return Self(cards: cards, nextIndex: 0)
    }

    public mutating func draw() throws -> Card {
        guard nextIndex < cards.count else { throw PokerRuleError.deckExhausted }
        defer { nextIndex += 1 }
        return cards[nextIndex]
    }

    public var remainingCards: [Card] {
        Array(cards[nextIndex...])
    }
}
