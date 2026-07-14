public enum HandEvaluator {
    public static func best(of cards: [Card]) throws -> HandRank {
        guard (5...7).contains(cards.count), Set(cards).count == cards.count else {
            throw PokerRuleError.invalidCards
        }

        return combinations(of: cards, taking: 5)
            .map(evaluateFive)
            .max()!
    }

    private static func evaluateFive(_ cards: [Card]) -> HandRank {
        let ranks = cards.map(\.rank.rawValue).sorted(by: >)
        let counts = Dictionary(grouping: ranks, by: { $0 }).mapValues(\.count)
        let groups = counts.sorted {
            $0.value == $1.value ? $0.key > $1.key : $0.value > $1.value
        }
        let isFlush = Set(cards.map(\.suit)).count == 1
        let straightHigh = straightHighCard(in: ranks)

        if let straightHigh, isFlush {
            return HandRank(category: .straightFlush, tieBreak: [straightHigh])
        }
        if groups[0].value == 4 {
            return HandRank(category: .fourOfAKind, tieBreak: [groups[0].key, groups[1].key])
        }
        if groups[0].value == 3, groups[1].value == 2 {
            return HandRank(category: .fullHouse, tieBreak: [groups[0].key, groups[1].key])
        }
        if isFlush {
            return HandRank(category: .flush, tieBreak: ranks)
        }
        if let straightHigh {
            return HandRank(category: .straight, tieBreak: [straightHigh])
        }
        if groups[0].value == 3 {
            let kickers = groups.dropFirst().map(\.key).sorted(by: >)
            return HandRank(category: .threeOfAKind, tieBreak: [groups[0].key] + kickers)
        }
        if groups[0].value == 2, groups[1].value == 2 {
            let pairs = groups.prefix(2).map(\.key).sorted(by: >)
            return HandRank(category: .twoPair, tieBreak: pairs + [groups[2].key])
        }
        if groups[0].value == 2 {
            let kickers = groups.dropFirst().map(\.key).sorted(by: >)
            return HandRank(category: .onePair, tieBreak: [groups[0].key] + kickers)
        }
        return HandRank(category: .highCard, tieBreak: ranks)
    }

    private static func straightHighCard(in descendingRanks: [Int]) -> Int? {
        let ascendingRanks = Array(Set(descendingRanks)).sorted()
        guard ascendingRanks.count == 5 else { return nil }
        if ascendingRanks == [2, 3, 4, 5, 14] { return 5 }
        return ascendingRanks[4] - ascendingRanks[0] == 4 ? ascendingRanks[4] : nil
    }

    private static func combinations(of cards: [Card], taking count: Int) -> [[Card]] {
        var result: [[Card]] = []

        func appendCombinations(startingAt index: Int, selected: [Card]) {
            if selected.count == count {
                result.append(selected)
                return
            }

            let cardsNeeded = count - selected.count
            guard index <= cards.count - cardsNeeded else { return }
            for nextIndex in index...(cards.count - cardsNeeded) {
                appendCombinations(
                    startingAt: nextIndex + 1,
                    selected: selected + [cards[nextIndex]]
                )
            }
        }

        appendCombinations(startingAt: 0, selected: [])
        return result
    }
}
