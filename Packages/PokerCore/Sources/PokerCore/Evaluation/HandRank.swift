public enum HandCategory: Int, Codable, Comparable, Sendable {
    case highCard
    case onePair
    case twoPair
    case threeOfAKind
    case straight
    case flush
    case fullHouse
    case fourOfAKind
    case straightFlush

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct HandRank: Codable, Equatable, Comparable, Sendable {
    public let category: HandCategory
    public let tieBreak: [Int]

    public init(category: HandCategory, tieBreak: [Int]) {
        self.category = category
        self.tieBreak = tieBreak
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.category != rhs.category {
            return lhs.category < rhs.category
        }
        return lhs.tieBreak.lexicographicallyPrecedes(rhs.tieBreak)
    }
}
