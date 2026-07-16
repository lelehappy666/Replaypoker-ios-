import PokerCore

enum RuleFeature: Hashable, Sendable {
    case holeCardStrength
    case position
    case madeHandStrength
    case drawPotential
    case potOdds
    case boardTexture
    case effectiveStack
    case publicActionHistory
    case opponentRange
}

struct RuleEvaluation: Equatable, Sendable {
    let features: Set<RuleFeature>
    let strengthBasisPoints: Int
    let positionBasisPoints: Int
    let drawBasisPoints: Int
    let potOddsBasisPoints: Int?
    let boardTextureBasisPoints: Int?
    let effectiveStackBigBlinds: Int?
    let publicAggressionBasisPoints: Int?
}

struct RuleBasedEvaluator: Sendable {
    func evaluate(
        _ observation: BotObservation,
        settings: BotSettings
    ) throws -> RuleEvaluation {
        let holeStrength = try PreflopRange.strengthBasisPoints(
            for: observation.ownHoleCards
        )
        let madeStrength = try madeHandStrength(observation)
        let drawStrength = drawBasisPoints(observation)
        let position = positionBasisPoints(observation)

        var features: Set<RuleFeature> = [
            .holeCardStrength, .position, .madeHandStrength, .drawPotential,
        ]
        var potOdds: Int?
        var texture: Int?
        var effectiveStack: Int?
        var publicAggression: Int?

        if settings.difficulty != .easy {
            features.formUnion([.potOdds, .boardTexture, .effectiveStack])
            potOdds = try potOddsBasisPoints(observation)
            texture = boardTextureBasisPoints(observation.communityCards)
            effectiveStack = try effectiveStackBigBlinds(observation)
        }
        if settings.difficulty == .hard {
            features.formUnion([.publicActionHistory, .opponentRange])
            publicAggression = publicAggressionBasisPoints(observation.actions)
        }

        let combinedStrength = observation.communityCards.isEmpty
            ? holeStrength
            : min(10_000, (holeStrength + madeStrength * 2 + drawStrength) / 4)

        return RuleEvaluation(
            features: features,
            strengthBasisPoints: combinedStrength,
            positionBasisPoints: position,
            drawBasisPoints: drawStrength,
            potOddsBasisPoints: potOdds,
            boardTextureBasisPoints: texture,
            effectiveStackBigBlinds: effectiveStack,
            publicAggressionBasisPoints: publicAggression
        )
    }

    func legalCandidates(for observation: BotObservation) throws -> [ActionCandidate] {
        let legal = observation.legalActions
        if let minimumBet = legal.minimumBet {
            guard let maximum = legal.maximumRaiseTo,
                  minimumBet.rawValue <= maximum.rawValue else {
                throw BotError.invalidObservation
            }
        }
        if let minimumRaise = legal.minimumRaiseTo {
            guard let maximum = legal.maximumRaiseTo,
                  minimumRaise.rawValue > observation.currentBet.rawValue,
                  minimumRaise.rawValue <= maximum.rawValue else {
                throw BotError.invalidObservation
            }
        }
        if let call = legal.callAmount, call.rawValue == 0 {
            throw BotError.invalidObservation
        }
        if legal.canAllIn, legal.maximumRaiseTo == nil {
            throw BotError.invalidObservation
        }

        var candidates: [ActionCandidate] = []
        if legal.canFold { candidates.append(ActionCandidate(kind: .fold)) }
        if legal.canCheck { candidates.append(ActionCandidate(kind: .check)) }
        if let call = legal.callAmount {
            candidates.append(
                ActionCandidate(kind: .call, minimumAmount: call, maximumAmount: call)
            )
        }
        if let minimum = legal.minimumBet, let maximum = legal.maximumRaiseTo {
            candidates.append(
                ActionCandidate(kind: .bet, minimumAmount: minimum, maximumAmount: maximum)
            )
        }
        if let minimum = legal.minimumRaiseTo, let maximum = legal.maximumRaiseTo {
            candidates.append(
                ActionCandidate(kind: .raise, minimumAmount: minimum, maximumAmount: maximum)
            )
        }
        guard !candidates.isEmpty else { throw BotError.invalidObservation }
        return candidates
    }

    private func madeHandStrength(_ observation: BotObservation) throws -> Int {
        let cards = observation.ownHoleCards + observation.communityCards
        guard cards.count <= 7, Set(cards).count == cards.count else {
            throw BotError.invalidObservation
        }
        guard cards.count >= 5 else {
            return try PreflopRange.strengthBasisPoints(for: observation.ownHoleCards)
        }
        let rank: HandRank
        do {
            rank = try HandEvaluator.best(of: cards)
        } catch {
            throw BotError.invalidObservation
        }
        let highTieBreak = rank.tieBreak.first ?? 0
        return min(10_000, rank.category.rawValue * 1_100 + highTieBreak * 70)
    }

    private func drawBasisPoints(_ observation: BotObservation) -> Int {
        let cards = observation.ownHoleCards + observation.communityCards
        let maximumSuitCount = Dictionary(grouping: cards, by: \.suit)
            .values.map(\.count).max() ?? 0
        let uniqueRanks = Set(cards.map(\.rank.rawValue)).sorted()
        let longestRun = longestConsecutiveRun(uniqueRanks)
        var score = 0
        if maximumSuitCount == 4 { score += 4_000 }
        else if maximumSuitCount >= 3 { score += 1_200 }
        if longestRun >= 4 { score += 3_500 }
        else if longestRun == 3 { score += 1_200 }
        return min(10_000, score)
    }

    private func positionBasisPoints(_ observation: BotObservation) -> Int {
        let seats = observation.publicSeats
            .filter { !$0.isSittingOut }
            .map(\.id)
            .sorted()
        guard let viewerIndex = seats.firstIndex(of: observation.viewer),
              let dealerIndex = seats.firstIndex(of: observation.config.dealer),
              !seats.isEmpty else {
            return 0
        }
        let distance = (viewerIndex - dealerIndex + seats.count) % seats.count
        if distance == 0 { return 9_000 }
        return min(8_500, 2_500 + distance * 700)
    }

    func potOddsBasisPoints(_ observation: BotObservation) throws -> Int {
        guard let call = observation.legalActions.callAmount else { return 0 }
        let (total, overflow) = observation.pot.rawValue.addingReportingOverflow(
            call.rawValue
        )
        guard !overflow, total > 0 else { throw BotError.invalidObservation }
        let (scaled, multiplyOverflow) = call.rawValue.multipliedReportingOverflow(
            by: 10_000
        )
        guard !multiplyOverflow else { throw BotError.invalidObservation }
        return scaled / total
    }

    private func boardTextureBasisPoints(_ cards: [Card]) -> Int {
        guard !cards.isEmpty else { return 0 }
        let maximumSuitCount = Dictionary(grouping: cards, by: \.suit)
            .values.map(\.count).max() ?? 0
        let longestRun = longestConsecutiveRun(Set(cards.map(\.rank.rawValue)).sorted())
        let hasPair = Set(cards.map(\.rank)).count < cards.count
        var score = max(0, maximumSuitCount - 1) * 1_500
        score += max(0, longestRun - 1) * 1_200
        if hasPair { score += 1_000 }
        return min(10_000, score)
    }

    func effectiveStackBigBlinds(_ observation: BotObservation) throws -> Int {
        guard let viewer = observation.publicSeats.first(where: {
            $0.id == observation.viewer
        }) else {
            throw BotError.invalidObservation
        }
        let opponentStack = observation.publicSeats
            .filter {
                $0.id != observation.viewer
                    && !$0.hasFolded && !$0.isSittingOut
            }
            .map(\.stack.rawValue)
            .max() ?? 0
        return min(viewer.stack.rawValue, opponentStack)
            / observation.config.bigBlind.rawValue
    }

    private func publicAggressionBasisPoints(_ actions: [RecordedAction]) -> Int {
        guard !actions.isEmpty else { return 0 }
        let aggressive = actions.reduce(into: 0) { count, recorded in
            switch recorded.action {
            case .bet, .raiseTo, .allIn: count += 1
            case .fold, .check, .call: break
            }
        }
        return aggressive * 10_000 / actions.count
    }

    private func longestConsecutiveRun(_ ranks: [Int]) -> Int {
        guard !ranks.isEmpty else { return 0 }
        var longest = 1
        var current = 1
        for index in ranks.indices.dropFirst() {
            if ranks[index] == ranks[index - 1] + 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }
}
