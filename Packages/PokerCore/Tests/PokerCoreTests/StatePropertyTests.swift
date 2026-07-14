import Foundation
import Testing
@testable import PokerCore

@Suite("StatePropertyTests")
struct StatePropertyTests {
    @Test func validatorRejectsDuplicateCards() throws {
        var state = try startedState(playerCount: 2, seed: 1)
        state.seats[0].holeCards[0] = state.seats[1].holeCards[0]

        #expect(throws: PokerRuleError.invalidState("duplicate cards")) {
            try StateValidator.validate(state)
        }
    }

    @Test func validatorRejectsCardCountOtherThanFiftyTwo() throws {
        var state = try startedState(playerCount: 2, seed: 2)
        state.seats[0].holeCards.removeLast()

        #expect(throws: PokerRuleError.invalidState("card count")) {
            try StateValidator.validate(state)
        }
    }

    @Test func validatorRejectsInvalidHoleCardCounts() throws {
        var state = try startedState(playerCount: 2, seed: 3)
        state.seats[1].holeCards.append(state.seats[0].holeCards.removeLast())

        #expect(throws: PokerRuleError.invalidState("invalid hole cards")) {
            try StateValidator.validate(state)
        }
    }

    @Test func validatorRejectsCommunityCardCountForStreet() throws {
        var state = try startedState(playerCount: 2, seed: 4)
        state.street = .flop
        state.forcedBringIn = Chips(rawValue: 0)!

        #expect(throws: PokerRuleError.invalidState("invalid community card count")) {
            try StateValidator.validate(state)
        }
    }

    @Test func validatorRejectsShortBoardAtMultiwayShowdown() throws {
        let preflop = try Fixtures.completePreflopState()
        var state = try HoldemEngine.advanceIfRoundComplete(preflop).state
        state.street = .showdown
        state.currentActor = nil

        #expect(throws: PokerRuleError.invalidState("invalid community card count")) {
            try StateValidator.validate(state)
        }
    }

    @Test func validatorReusesStructuralBettingValidation() throws {
        let valid = try startedState(playerCount: 3, seed: 5)

        var duplicateSeat = valid
        duplicateSeat.seats[1] = duplicateSeat.seats[0]
        #expect(throws: PokerRuleError.invalidState("duplicate seat ids")) {
            try StateValidator.validate(duplicateSeat)
        }

        var invalidActor = valid
        invalidActor.currentActor = SeatID(rawValue: 8)!
        #expect(throws: PokerRuleError.invalidState("invalid actor")) {
            try StateValidator.validate(invalidActor)
        }

        var badCommitment = valid
        badCommitment.seats[0].committedThisHand = Chips(rawValue: 0)!
        #expect(throws: PokerRuleError.invalidState("hand commitment below street commitment")) {
            try StateValidator.validate(badCommitment)
        }

        var badPot = valid
        badPot.unallocatedPot = Chips(rawValue: valid.unallocatedPot.rawValue + 1)!
        #expect(throws: PokerRuleError.invalidState("unallocated pot mismatch")) {
            try StateValidator.validate(badPot)
        }

        var badAccounting = valid
        badAccounting.seats[0].stack = Chips(
            rawValue: badAccounting.seats[0].stack.rawValue - 1
        )!
        #expect(throws: PokerRuleError.invalidState("chip conservation")) {
            try StateValidator.validate(badAccounting)
        }

        var badBlindPositions = valid
        badBlindPositions.smallBlindSeat = badBlindPositions.bigBlindSeat
        #expect(throws: PokerRuleError.invalidState("invalid blind seats")) {
            try StateValidator.validate(badBlindPositions)
        }
    }

    @Test func chipsRejectNegativeDecodedValues() throws {
        let data = Data("-1".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Chips.self, from: data)
        }
    }

    @Test func validatorRejectsTerminalFieldCorruption() throws {
        let completed = try completedState(seed: 6)

        var terminalCommitment = completed
        terminalCommitment.seats[0].stack = Chips(
            rawValue: terminalCommitment.seats[0].stack.rawValue - 1
        )!
        terminalCommitment.seats[0].committedThisHand = Chips(rawValue: 1)!
        terminalCommitment.unallocatedPot = Chips(rawValue: 1)!
        #expect(throws: PokerRuleError.invalidState("terminal commitments")) {
            try StateValidator.validate(terminalCommitment)
        }

        var badAwards = completed
        badAwards.awards = [:]
        #expect(throws: PokerRuleError.invalidState("settlement accounting")) {
            try StateValidator.validate(badAwards)
        }

        var ineligibleAward = try Fixtures.resolveBoardPlayingTie().state
        let winner = try #require(ineligibleAward.awards.keys.first)
        let otherSeat = try #require(
            ineligibleAward.activeSeats.map(\.id).first { $0 != winner }
        )
        ineligibleAward.settledPots = ineligibleAward.settledPots.map {
            Pot(amount: $0.amount, eligible: [otherSeat])
        }
        #expect(throws: PokerRuleError.invalidState("ineligible award")) {
            try StateValidator.validate(ineligibleAward)
        }

        var wrongWinners = try Fixtures.resolveBoardPlayingTie().state
        let onlyWinner = try #require(wrongWinners.awards.keys.first)
        let totalAwards = wrongWinners.awards.values.reduce(0) { $0 + $1.rawValue }
        wrongWinners.awards = [onlyWinner: Chips(rawValue: totalAwards)!]
        #expect(throws: PokerRuleError.invalidState("settlement awards mismatch")) {
            try StateValidator.validate(wrongWinners)
        }
    }

    @Test func validatorRejectsSettlementFieldsBeforeCompletion() throws {
        let started = try startedState(playerCount: 2, seed: 7)
        let actor = try #require(started.currentActor)
        var showdown = try HoldemEngine.applying(
            .fold,
            by: actor,
            to: started
        ).state
        showdown.awards = [SeatID(rawValue: 1)!: Chips(rawValue: 1)!]

        #expect(throws: PokerRuleError.invalidState("premature settlement")) {
            try StateValidator.validate(showdown)
        }
    }

    @Test func fiveHundredSeededHandsPreserveCoreInvariantsAndAreDeterministic() throws {
        let first = try runBatch()
        let second = try runBatch()
        #expect(first == second)
        #expect(first.count == 500)
    }

    private func runBatch() throws -> [SimulationSummary] {
        try (1...500).map { seed in
            let playerCount = 2 + seed % 8
            do {
                let result = try Simulation.playLegalHand(
                    seed: UInt64(seed),
                    playerCount: playerCount
                )
                try StateValidator.validate(result.state)
                #expect(result.state.street == .complete, "seed=\(seed), actions=\(result.actions)")
                #expect(
                    result.state.totalSeatChips == result.initialTotalChips,
                    "seed=\(seed), actions=\(result.actions)"
                )
                #expect(
                    Set(result.allDealtCards).count == result.allDealtCards.count,
                    "seed=\(seed), actions=\(result.actions)"
                )
                try result.validateAudit(seed: UInt64(seed))
                return result.summary
            } catch {
                Issue.record("seed=\(seed), playerCount=\(playerCount), error=\(error)")
                throw error
            }
        }
    }

    private func startedState(playerCount: Int, seed: UInt64) throws -> HoldemState {
        try HoldemEngine.start(
            config: HandConfig(
                smallBlind: Chips(rawValue: 5)!,
                bigBlind: Chips(rawValue: 10)!,
                dealer: SeatID(rawValue: Int(seed % UInt64(playerCount)))!
            ),
            stacks: Dictionary(uniqueKeysWithValues: (0..<playerCount).map {
                (SeatID(rawValue: $0)!, Chips(rawValue: 1_000)!)
            }),
            seed: seed
        ).state
    }

    private func completedState(seed: UInt64) throws -> HoldemState {
        let started = try startedState(playerCount: 2, seed: seed)
        let actor = try #require(started.currentActor)
        let showdown = try HoldemEngine.applying(.fold, by: actor, to: started).state
        return try HoldemEngine.advanceIfRoundComplete(showdown).state
    }
}

private struct SimulationResult {
    let state: HoldemState
    let initialTotalChips: Int
    let actions: [RecordedAction]
    let events: [GameEvent]

    var allDealtCards: [Card] {
        state.seats.flatMap(\.holeCards) + state.communityCards
    }

    var summary: SimulationSummary {
        SimulationSummary(
            state: state,
            actions: actions,
            events: events
        )
    }

    func validateAudit(seed: UInt64) throws {
        #expect(events.first == .handStarted(seed: seed), "seed=\(seed), actions=\(actions)")
        #expect(events.last == .handCompleted, "seed=\(seed), actions=\(actions)")
        #expect(
            events.filter { $0 == .handCompleted }.count == 1,
            "seed=\(seed), actions=\(actions)"
        )

        let recordedEvents = events.compactMap { event -> RecordedAction? in
            guard case let .actionApplied(seat, action) = event else { return nil }
            return RecordedAction(seat: seat, street: .preflop, action: action)
        }
        #expect(
            zip(recordedEvents, actions).allSatisfy { $0.seat == $1.seat && $0.action == $1.action }
                && recordedEvents.count == actions.count,
            "seed=\(seed), actions=\(actions)"
        )
        #expect(state.actionHistory == actions, "seed=\(seed), actions=\(actions)")

        let createdPots = events.compactMap { event -> Pot? in
            guard case let .potCreated(pot) = event else { return nil }
            return pot
        }
        #expect(createdPots == state.settledPots, "seed=\(seed), actions=\(actions)")

        let returnedChips = Dictionary(uniqueKeysWithValues: events.compactMap {
            event -> (SeatID, Chips)? in
            guard case let .uncalledBetReturned(seat, amount) = event else { return nil }
            return (seat, amount)
        })
        #expect(
            returnedChips == state.uncalledReturns,
            "seed=\(seed), actions=\(actions)"
        )

        var eventAwards: [SeatID: Int] = [:]
        let awardEvents = events.compactMap { event -> (Int, [SeatID], [SeatID: Chips])? in
            guard case let .potAwarded(index, winners, amounts) = event else { return nil }
            return (index, winners, amounts)
        }
        #expect(awardEvents.count == state.settledPots.count, "seed=\(seed), actions=\(actions)")
        for (expectedIndex, awardEvent) in awardEvents.enumerated() {
            let (index, winners, amounts) = awardEvent
            #expect(index == expectedIndex, "seed=\(seed), actions=\(actions)")
            let pot = state.settledPots[index]
            #expect(winners.allSatisfy(pot.eligible.contains), "seed=\(seed), actions=\(actions)")
            #expect(Set(winners) == Set(amounts.keys), "seed=\(seed), actions=\(actions)")
            #expect(
                amounts.values.reduce(0) { $0 + $1.rawValue } == pot.amount.rawValue,
                "seed=\(seed), actions=\(actions)"
            )
            for (seat, amount) in amounts {
                eventAwards[seat, default: 0] += amount.rawValue
            }
        }
        #expect(
            eventAwards == state.awards.mapValues(\.rawValue),
            "seed=\(seed), actions=\(actions)"
        )
    }
}

private struct SimulationSummary: Equatable {
    let state: HoldemState
    let actions: [RecordedAction]
    let events: [GameEvent]
}

private enum Simulation {
    static func playLegalHand(seed: UInt64, playerCount: Int) throws -> SimulationResult {
        var generator = SeededGenerator(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
        var actions: [RecordedAction] = []
        do {
            return try playLegalHand(
                seed: seed,
                playerCount: playerCount,
                generator: &generator,
                actions: &actions
            )
        } catch {
            throw PokerRuleError.invalidState(
                "simulation seed=\(seed), playerCount=\(playerCount), "
                    + "actions=\(actions), error=\(error)"
            )
        }
    }

    private static func playLegalHand(
        seed: UInt64,
        playerCount: Int,
        generator: inout SeededGenerator,
        actions: inout [RecordedAction]
    ) throws -> SimulationResult {
        let dealer = SeatID(rawValue: Int(seed % UInt64(playerCount)))!
        let stacks = Dictionary(uniqueKeysWithValues: (0..<playerCount).map { index in
            (SeatID(rawValue: index)!, Chips(rawValue: 1_000)!)
        })
        let started = try HoldemEngine.start(
            config: HandConfig(
                smallBlind: Chips(rawValue: 5)!,
                bigBlind: Chips(rawValue: 10)!,
                dealer: dealer
            ),
            stacks: stacks,
            seed: seed
        )
        var state = started.state
        var events = started.events
        try StateValidator.validate(state)

        for _ in 0..<1_000 where state.street != .complete {
            try StateValidator.validate(state)
            let transition: EngineResult
            if let actor = state.currentActor {
                let legal = try BettingRules.legalActions(for: actor, in: state)
                let candidates = actionCandidates(from: legal)
                guard !candidates.isEmpty else {
                    throw PokerRuleError.invalidState("simulation has no legal action")
                }
                let action = candidates[Int(generator.next() % UInt64(candidates.count))]
                actions.append(RecordedAction(seat: actor, street: state.street, action: action))
                transition = try HoldemEngine.applying(action, by: actor, to: state)
            } else {
                transition = try HoldemEngine.advanceIfRoundComplete(state)
            }
            guard transition.state != state else {
                throw PokerRuleError.invalidState("simulation made no progress")
            }
            state = transition.state
            events.append(contentsOf: transition.events)
            try StateValidator.validate(state)
        }

        guard state.street == .complete else {
            throw PokerRuleError.invalidState("simulation step limit")
        }
        return SimulationResult(
            state: state,
            initialTotalChips: started.state.initialTotalChips,
            actions: actions,
            events: events
        )
    }

    private static func actionCandidates(from legal: LegalActionSet) -> [PlayerAction] {
        var result: [PlayerAction] = []
        if legal.canFold { result.append(.fold) }
        if legal.canCheck { result.append(.check) }
        if legal.callAmount != nil { result.append(.call) }
        if let minimumBet = legal.minimumBet { result.append(.bet(minimumBet)) }
        if let minimumRaiseTo = legal.minimumRaiseTo { result.append(.raiseTo(minimumRaiseTo)) }
        if legal.canAllIn { result.append(.allIn) }
        return result
    }
}
