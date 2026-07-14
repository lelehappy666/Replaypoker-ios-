@testable import PokerCore

enum Cards {
    static func parse(_ value: String) throws -> [Card] {
        try value.split(separator: " ").map { token in
            guard token.count == 2 else { throw PokerRuleError.invalidCards }

            let characters = Array(token)
            let rank: Rank
            switch characters[0] {
            case "2": rank = .two
            case "3": rank = .three
            case "4": rank = .four
            case "5": rank = .five
            case "6": rank = .six
            case "7": rank = .seven
            case "8": rank = .eight
            case "9": rank = .nine
            case "T": rank = .ten
            case "J": rank = .jack
            case "Q": rank = .queen
            case "K": rank = .king
            case "A": rank = .ace
            default: throw PokerRuleError.invalidCards
            }

            let suit: Suit
            switch characters[1] {
            case "c": suit = .clubs
            case "d": suit = .diamonds
            case "h": suit = .hearts
            case "s": suit = .spades
            default: throw PokerRuleError.invalidCards
            }

            return Card(rank: rank, suit: suit)
        }
    }
}
