import PokerCore

struct EquityEstimate: Equatable, Sendable {
    let winBasisPoints: Int
    let tieBasisPoints: Int
    let effectiveBasisPoints: Int
    let iterations: Int
}

protocol EquityEstimating: Sendable {
    func estimate(
        _ observation: BotObservation,
        iterations: Int,
        seed: UInt64
    ) async throws -> EquityEstimate
}

struct MonteCarloEstimator: EquityEstimating, Sendable {
    private static let equityUnitsPerPot: Int64 = 2_520

    func estimate(
        _ observation: BotObservation,
        iterations: Int,
        seed: UInt64
    ) async throws -> EquityEstimate {
        guard (1...10_000_000).contains(iterations),
              observation.ownHoleCards.count == 2,
              expectedCommunityCount(for: observation.street)
                == observation.communityCards.count else {
            throw BotError.invalidObservation
        }

        let publicSeatIDs = observation.publicSeats.map(\.id)
        guard (2...9).contains(publicSeatIDs.count),
              Set(publicSeatIDs).count == publicSeatIDs.count,
              publicSeatIDs.contains(observation.viewer),
              publicSeatIDs.contains(observation.config.dealer) else {
            throw BotError.invalidObservation
        }

        let activeOpponents = observation.publicSeats.filter {
            $0.id != observation.viewer
                && !$0.hasFolded
                && !$0.isSittingOut
        }
        guard !activeOpponents.isEmpty else {
            throw BotError.invalidObservation
        }

        let knownCards = observation.ownHoleCards + observation.communityCards
        let sampler = try UnknownCardSampler(knownCards: knownCards)
        let missingBoardCards = 5 - observation.communityCards.count
        let cardsNeeded = activeOpponents.count * 2 + missingBoardCards
        var generator = BotSeededGenerator(seed: seed)
        var wins: Int64 = 0
        var ties: Int64 = 0
        var effectiveUnits: Int64 = 0

        for iteration in 0..<iterations {
            if iteration.isMultiple(of: 32) {
                try Task.checkCancellation()
            }
            let sampled = try sampler.sample(count: cardsNeeded, using: &generator)
            var cursor = 0
            var opponentCards: [[Card]] = []
            opponentCards.reserveCapacity(activeOpponents.count)
            for _ in activeOpponents {
                opponentCards.append([sampled[cursor], sampled[cursor + 1]])
                cursor += 2
            }
            let board = observation.communityCards
                + Array(sampled[cursor..<(cursor + missingBoardCards)])

            let heroRank = try rank(
                holeCards: observation.ownHoleCards,
                board: board
            )
            let opponentRanks = try opponentCards.map {
                try rank(holeCards: $0, board: board)
            }
            guard let bestRank = ([heroRank] + opponentRanks).max() else {
                throw BotError.invalidObservation
            }

            if heroRank == bestRank {
                let winnerCount = 1 + opponentRanks.filter { $0 == heroRank }.count
                effectiveUnits += Self.equityUnitsPerPot / Int64(winnerCount)
                if winnerCount == 1 { wins += 1 }
                else { ties += 1 }
            }
        }
        try Task.checkCancellation()

        let iterationCount = Int64(iterations)
        return EquityEstimate(
            winBasisPoints: Int(wins * 10_000 / iterationCount),
            tieBasisPoints: Int(ties * 10_000 / iterationCount),
            effectiveBasisPoints: Int(
                effectiveUnits * 10_000
                    / (iterationCount * Self.equityUnitsPerPot)
            ),
            iterations: iterations
        )
    }

    private func expectedCommunityCount(for street: Street) -> Int? {
        switch street {
        case .preflop: 0
        case .flop: 3
        case .turn: 4
        case .river: 5
        case .showdown, .complete: nil
        }
    }

    private func rank(holeCards: [Card], board: [Card]) throws -> HandRank {
        do {
            return try HandEvaluator.best(of: holeCards + board)
        } catch {
            throw BotError.invalidObservation
        }
    }
}
