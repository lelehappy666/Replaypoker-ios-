import PokerCore

enum PreflopRange {
    static func strengthBasisPoints(for cards: [Card]) throws -> Int {
        guard cards.count == 2, cards[0] != cards[1] else {
            throw BotError.invalidObservation
        }

        let ranks = cards.map(\.rank.rawValue).sorted(by: >)
        let high = ranks[0]
        let low = ranks[1]
        var score = high * 360 + low * 140

        if high == low {
            score += 3_000 + high * 80
        } else {
            if cards[0].suit == cards[1].suit { score += 450 }
            let gap = high - low
            if gap == 1 { score += 450 }
            else if gap == 2 { score += 250 }
            else if gap >= 5 { score -= min(700, (gap - 4) * 140) }
            if high == Rank.ace.rawValue && low >= Rank.ten.rawValue {
                score += 500
            }
        }

        return min(10_000, max(0, score))
    }
}
