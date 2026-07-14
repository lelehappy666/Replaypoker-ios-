public enum Suit: Int, CaseIterable, Codable, Sendable {
    case clubs, diamonds, hearts, spades
}

public enum Rank: Int, CaseIterable, Codable, Comparable, Sendable {
    case two = 2, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Card: Codable, Hashable, Comparable, Sendable {
    public let rank: Rank
    public let suit: Suit

    public static let fullDeck = Suit.allCases.flatMap { suit in
        Rank.allCases.map { Card(rank: $0, suit: suit) }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank == rhs.rank ? lhs.suit.rawValue < rhs.suit.rawValue : lhs.rank < rhs.rank
    }
}
