struct Deck: Codable, Equatable, Sendable {
    private var cards: [Card]
    private var nextIndex: Int

    init(cards: [Card], nextIndex: Int) {
        self.cards = cards
        self.nextIndex = nextIndex
    }

    public static func shuffled(seed: UInt64) -> Self {
        var cards = Card.fullDeck
        var generator = SeededGenerator(seed: seed)
        cards.shuffle(using: &generator)
        return Self(cards: cards, nextIndex: 0)
    }

    public mutating func draw() throws -> Card {
        guard nextIndex >= 0 else {
            throw PokerRuleError.invalidState("invalid deck position")
        }
        guard nextIndex < cards.count else { throw PokerRuleError.deckExhausted }
        defer { nextIndex += 1 }
        return cards[nextIndex]
    }

    public var remainingCards: [Card] {
        guard (0...cards.count).contains(nextIndex) else { return [] }
        return Array(cards[nextIndex...])
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cards = try container.decode([Card].self, forKey: .cards)
        let nextIndex = try container.decode(Int.self, forKey: .nextIndex)
        guard cards.count == Card.fullDeck.count,
              Set(cards) == Set(Card.fullDeck),
              (0...cards.count).contains(nextIndex) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid deck")
            )
        }
        self.cards = cards
        self.nextIndex = nextIndex
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cards, forKey: .cards)
        try container.encode(nextIndex, forKey: .nextIndex)
    }

    private enum CodingKeys: String, CodingKey {
        case cards, nextIndex
    }
}
