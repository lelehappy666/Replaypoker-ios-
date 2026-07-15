import PokerCore

struct BotSeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

struct UnknownCardSampler: Sendable {
    private let availableCards: [Card]

    init(knownCards: [Card]) throws {
        let known = Set(knownCards)
        guard known.count == knownCards.count,
              known.isSubset(of: Set(Card.fullDeck)) else {
            throw BotError.invalidObservation
        }
        availableCards = Card.fullDeck.filter { !known.contains($0) }
    }

    func sample(
        count: Int,
        using generator: inout BotSeededGenerator
    ) throws -> [Card] {
        guard count >= 0, count <= availableCards.count else {
            throw BotError.invalidObservation
        }
        guard count > 0 else { return [] }

        var pool = availableCards
        for index in 0..<count {
            let remaining = pool.count - index
            let offset = Int(generator.next() % UInt64(remaining))
            pool.swapAt(index, index + offset)
        }
        return Array(pool.prefix(count))
    }
}
