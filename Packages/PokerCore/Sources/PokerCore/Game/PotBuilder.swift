public enum PotBuilder {
    public static func build(
        commitments: [SeatID: Chips],
        folded: Set<SeatID>
    ) throws -> [Pot] {
        let commitmentTotal = try checkedSum(commitments.values.map(\.rawValue))
        let levels = Set(
            commitments.values.lazy.map(\.rawValue).filter { $0 > 0 }
        ).sorted()

        var previousLevel = 0
        var pots: [Pot] = []
        var potTotal = 0

        for level in levels {
            let participating = commitments.filter { $0.value.rawValue >= level }
            let layerWidth = level - previousLevel
            let amount = try checkedMultiply(layerWidth, participating.count)
            let eligible = Set(participating.keys).subtracting(folded)

            guard !eligible.isEmpty else {
                throw PokerRuleError.invalidState("pot has no eligible seats")
            }

            pots.append(Pot(amount: Chips(rawValue: amount)!, eligible: eligible))
            potTotal = try checkedAdd(potTotal, amount)
            previousLevel = level
        }

        guard potTotal == commitmentTotal else {
            throw PokerRuleError.invalidState("pot total mismatch")
        }
        return pots
    }

    public static func awards(
        for pots: [Pot],
        ranks: [SeatID: HandRank],
        dealer: SeatID
    ) throws -> [SeatID: Chips] {
        let potTotal = try checkedSum(pots.map { $0.amount.rawValue })
        var awards: [SeatID: Chips] = [:]

        for pot in pots {
            guard !pot.eligible.isEmpty else {
                throw PokerRuleError.invalidState("pot has no eligible seats")
            }

            let rankedSeats = try pot.eligible.map { seat -> (SeatID, HandRank) in
                guard let rank = ranks[seat] else {
                    throw PokerRuleError.invalidState("missing hand rank")
                }
                return (seat, rank)
            }
            let bestRank = rankedSeats.map(\.1).max()!
            let winners = rankedSeats.lazy
                .filter { $0.1 == bestRank }
                .map(\.0)
                .sorted { clockwiseDistance(from: dealer, to: $0)
                    < clockwiseDistance(from: dealer, to: $1) }

            let share = pot.amount.rawValue / winners.count
            let remainder = pot.amount.rawValue % winners.count
            for (index, winner) in winners.enumerated() {
                let amount = try checkedAdd(share, index < remainder ? 1 : 0)
                let accumulated = try checkedAdd(awards[winner]?.rawValue ?? 0, amount)
                awards[winner] = Chips(rawValue: accumulated)!
            }
        }

        let awardTotal = try checkedSum(awards.values.map(\.rawValue))
        guard awardTotal == potTotal else {
            throw PokerRuleError.invalidState("award total mismatch")
        }
        return awards
    }

    private static func clockwiseDistance(from dealer: SeatID, to seat: SeatID) -> Int {
        let distance = (seat.rawValue - dealer.rawValue + 9) % 9
        return distance == 0 ? 9 : distance
    }

    private static func checkedSum(_ values: [Int]) throws -> Int {
        try values.reduce(0, checkedAdd)
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw PokerRuleError.invalidState("chip arithmetic overflow")
        }
        return result
    }

    private static func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw PokerRuleError.invalidState("chip arithmetic overflow")
        }
        return result
    }
}
