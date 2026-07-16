import PokerCore

enum CurrentHandPresentation {
    static func text(
        holeCards: [Card],
        communityCards: [Card]
    ) -> String? {
        guard holeCards.count == 2,
              Set(holeCards + communityCards).count
                == holeCards.count + communityCards.count
        else {
            return nil
        }

        guard communityCards.count >= 3 else {
            return "起手牌：\(startingHandText(holeCards))"
        }

        guard let rank = try? HandEvaluator.best(of: holeCards + communityCards) else {
            return nil
        }
        return "当前牌型：\(rankText(rank))"
    }

    private static func startingHandText(_ cards: [Card]) -> String {
        let sorted = cards.sorted { $0.rank > $1.rank }
        let ranks = sorted.map { rankText($0.rank.rawValue) }.joined()
        if sorted[0].rank == sorted[1].rank {
            return "\(ranks) 对子"
        }
        return "\(ranks) \(sorted[0].suit == sorted[1].suit ? "同花" : "不同花")"
    }

    private static func rankText(_ rank: HandRank) -> String {
        let values = rank.tieBreak
        switch rank.category {
        case .highCard:
            return "高牌 \(rankText(values[0]))"
        case .onePair:
            return "一对 \(rankText(values[0]))"
        case .twoPair:
            return "两对，\(rankText(values[0])) 和 \(rankText(values[1]))"
        case .threeOfAKind:
            return "三条 \(rankText(values[0]))"
        case .straight:
            return "顺子，\(rankText(values[0])) 高"
        case .flush:
            return "同花，\(rankText(values[0])) 高"
        case .fullHouse:
            return "葫芦，\(rankText(values[0])) 带 \(rankText(values[1]))"
        case .fourOfAKind:
            return "四条 \(rankText(values[0]))"
        case .straightFlush:
            return "同花顺，\(rankText(values[0])) 高"
        }
    }

    private static func rankText(_ value: Int) -> String {
        switch value {
        case 14: "A"
        case 13: "K"
        case 12: "Q"
        case 11: "J"
        default: String(value)
        }
    }
}
