extension CompletedHandRecord {
    package func validateForPersistence() throws {
        try CompletedHandRecordValidator.validate(self)
    }
}

private enum CompletedHandRecordValidator {
    static func validate(_ record: CompletedHandRecord) throws {
        let knownSeats = Set(record.startingStacks.keys)
        guard (2...9).contains(knownSeats.count),
              knownSeats.contains(record.config.dealer),
              Set(record.holeCardsBySeat.keys) == knownSeats,
              Set(record.settledCommitments.keys) == knownSeats,
              Set(record.settledContributions.keys) == knownSeats,
              Set(record.finalStacks.keys) == knownSeats,
              Set(record.chipDeltas.keys) == knownSeats,
              record.actions.allSatisfy({ knownSeats.contains($0.seat) })
        else {
            throw invalid("record seat mismatch")
        }

        let holeCards = record.holeCardsBySeat.values.flatMap { $0 }
        let allCards = holeCards + record.communityCards
        guard record.holeCardsBySeat.values.allSatisfy({ $0.count == 2 }),
              Set(allCards).count == allCards.count
        else {
            throw invalid("record card mismatch")
        }

        let startingTotal = try checkedSum(record.startingStacks.values.map(\.rawValue))
        guard startingTotal == record.initialTotalChips else {
            throw invalid("record initial total mismatch")
        }

        let activeSeats = record.pots.reduce(into: Set<SeatID>()) {
            $0.formUnion($1.eligible)
        }
        guard !activeSeats.isEmpty,
              activeSeats.isSubset(of: knownSeats),
              record.pots.allSatisfy({
                  $0.amount.rawValue > 0
                      && !$0.eligible.isEmpty
                      && $0.eligible.isSubset(of: activeSeats)
              })
        else {
            throw invalid("record pot mismatch")
        }

        let validCommunityCardCount = activeSeats.count > 1
            ? record.communityCards.count == 5
            : [0, 3, 4, 5].contains(record.communityCards.count)
        guard validCommunityCardCount else {
            throw invalid("record community card mismatch")
        }

        let highestActiveCommitment = try activeSeats.map { seat in
            guard let commitment = record.settledCommitments[seat] else {
                throw invalid("record commitment mismatch")
            }
            return commitment.rawValue
        }.max()
        guard let highestActiveCommitment, highestActiveCommitment > 0 else {
            throw invalid("record commitment mismatch")
        }

        var expectedContributions: [SeatID: Chips] = [:]
        var expectedReturns: [SeatID: Chips] = [:]
        for seat in knownSeats {
            guard let starting = record.startingStacks[seat],
                  let commitment = record.settledCommitments[seat],
                  commitment <= starting
            else {
                throw invalid("record commitment mismatch")
            }

            let contribution = try Chips(min(commitment.rawValue, highestActiveCommitment))
            expectedContributions[seat] = contribution
            let returned = commitment.rawValue - contribution.rawValue
            if returned > 0 {
                expectedReturns[seat] = try Chips(returned)
            }
        }
        guard record.settledContributions == expectedContributions,
              record.uncalledReturns == expectedReturns
        else {
            throw invalid("record contribution mismatch")
        }

        let folded = knownSeats.subtracting(activeSeats)
        guard try PotBuilder.build(
            commitments: record.settledContributions,
            folded: folded
        ) == record.pots else {
            throw invalid("record pot mismatch")
        }

        let expectedRanks: [SeatID: HandRank]
        if record.communityCards.count == 5 {
            expectedRanks = try Dictionary(uniqueKeysWithValues: knownSeats.map { seat in
                guard let cards = record.holeCardsBySeat[seat] else {
                    throw invalid("record card mismatch")
                }
                return (seat, try HandEvaluator.best(of: cards + record.communityCards))
            })
        } else {
            expectedRanks = [:]
        }
        guard record.handRanksBySeat == expectedRanks else {
            throw invalid("record rank mismatch")
        }

        let awardRanks: [SeatID: HandRank]
        if record.communityCards.count == 5 {
            awardRanks = expectedRanks
        } else {
            guard activeSeats.count == 1, let onlyActiveSeat = activeSeats.first else {
                throw invalid("record rank mismatch")
            }
            awardRanks = [
                onlyActiveSeat: HandRank(category: .highCard, tieBreak: []),
            ]
        }
        guard try PotBuilder.awards(
            for: record.pots,
            ranks: awardRanks,
            dealer: record.config.dealer
        ) == record.awards else {
            throw invalid("record award mismatch")
        }

        for seat in knownSeats {
            guard let starting = record.startingStacks[seat],
                  let commitment = record.settledCommitments[seat],
                  let final = record.finalStacks[seat],
                  let delta = record.chipDeltas[seat]
            else {
                throw invalid("record stack mismatch")
            }

            let afterCommitment = starting.rawValue - commitment.rawValue
            let expectedFinal = try checkedSum([
                afterCommitment,
                record.uncalledReturns[seat]?.rawValue ?? 0,
                record.awards[seat]?.rawValue ?? 0,
            ])
            let (expectedDelta, deltaOverflow) = final.rawValue
                .subtractingReportingOverflow(starting.rawValue)
            guard !deltaOverflow,
                  final.rawValue == expectedFinal,
                  delta == expectedDelta
            else {
                throw invalid("record stack mismatch")
            }
        }

        let finalTotal = try checkedSum(record.finalStacks.values.map(\.rawValue))
        let deltaTotal = try checkedSum(Array(record.chipDeltas.values))
        guard finalTotal == record.initialTotalChips, deltaTotal == 0 else {
            throw invalid("record chip conservation mismatch")
        }

        let replayed = try HoldemEngine.replay(record)
        let replayedHoleCards = Dictionary(uniqueKeysWithValues: replayed.dealtInSeats.map {
            ($0.id, $0.holeCards)
        })
        let replayedFinalStacks = Dictionary(uniqueKeysWithValues: replayed.seats.map {
            ($0.id, $0.stack)
        })
        guard replayed.config == record.config,
              replayedHoleCards == record.holeCardsBySeat,
              replayed.communityCards == record.communityCards,
              replayed.actionHistory == record.actions,
              replayed.settledPots == record.pots,
              replayed.awards == record.awards,
              replayed.uncalledReturns == record.uncalledReturns,
              replayed.startingStacks == record.startingStacks,
              replayed.settledCommitments == record.settledCommitments,
              replayed.settledContributions == record.settledContributions,
              replayed.initialTotalChips == record.initialTotalChips,
              replayedFinalStacks == record.finalStacks
        else {
            throw invalid("record replay mismatch")
        }
    }

    private static func checkedSum(_ values: [Int]) throws -> Int {
        try values.reduce(0) { total, value in
            let (result, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { throw invalid("record chip arithmetic overflow") }
            return result
        }
    }

    private static func invalid(_ description: String) -> PokerRuleError {
        .invalidState(description)
    }
}
