import Foundation
import Testing
@testable import PokerCore

@Suite("StatePropertyTests")
struct StatePropertyTests {
    @Test func startRejectsZeroStackSeat() throws {
        #expect(throws: PokerRuleError.invalidState("non-positive stack")) {
            try HoldemEngine.start(
                config: Fixtures.standardConfig(dealer: 0),
                stacks: [
                    SeatID(rawValue: 0)!: Chips(rawValue: 1_000)!,
                    SeatID(rawValue: 1)!: Chips(rawValue: 0)!,
                ],
                seed: 1
            )
        }
    }

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
        state.currentActor = BettingActorResolver.expectedActor(in: state)

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

        var shiftedStacks = valid
        shiftedStacks.seats[0].stack = Chips(
            rawValue: shiftedStacks.seats[0].stack.rawValue + 1
        )!
        shiftedStacks.seats[1].stack = Chips(
            rawValue: shiftedStacks.seats[1].stack.rawValue - 1
        )!
        #expect(throws: PokerRuleError.invalidState("live stack mismatch")) {
            try StateValidator.validate(shiftedStacks)
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

    @Test func validatorAuditsSettlementSourcesReturnsAndFinalStacks() throws {
        let completed = try shortBigBlindCompletion(seed: 200)
        let seatZero = SeatID(rawValue: 0)!
        let seatOne = SeatID(rawValue: 1)!

        #expect(completed.startingStacks == [
            seatZero: Chips(rawValue: 1_000)!,
            seatOne: Chips(rawValue: 30)!,
        ])
        #expect(completed.settledCommitments == [
            seatZero: Chips(rawValue: 50)!,
            seatOne: Chips(rawValue: 30)!,
        ])
        #expect(completed.settledContributions == [
            seatZero: Chips(rawValue: 30)!,
            seatOne: Chips(rawValue: 30)!,
        ])

        var wrongReturn = completed
        wrongReturn.uncalledReturns[seatZero] = Chips(rawValue: 21)!
        #expect(throws: PokerRuleError.invalidState("settlement return mismatch")) {
            try StateValidator.validate(wrongReturn)
        }

        var wrongStack = completed
        wrongStack.seats[0].stack = Chips(rawValue: wrongStack.seats[0].stack.rawValue + 1)!
        wrongStack.seats[1].stack = Chips(rawValue: wrongStack.seats[1].stack.rawValue - 1)!
        #expect(throws: PokerRuleError.invalidState("settlement stack mismatch")) {
            try StateValidator.validate(wrongStack)
        }

        var wrongContribution = completed
        wrongContribution.settledContributions[seatZero] = Chips(rawValue: 31)!
        wrongContribution.uncalledReturns[seatZero] = Chips(rawValue: 19)!
        #expect(throws: PokerRuleError.invalidState("settlement contribution mismatch")) {
            try StateValidator.validate(wrongContribution)
        }

        var missingSource = completed
        missingSource.settledCommitments.removeValue(forKey: seatOne)
        #expect(throws: PokerRuleError.invalidState("settlement source mismatch")) {
            try StateValidator.validate(missingSource)
        }

        var unknownSource = completed
        unknownSource.settledContributions[SeatID(rawValue: 8)!] = Chips(rawValue: 0)!
        #expect(throws: PokerRuleError.invalidState("settlement source mismatch")) {
            try StateValidator.validate(unknownSource)
        }

        var coordinatedCorruption = completed
        coordinatedCorruption.settledContributions = [
            seatZero: Chips(rawValue: 20)!,
            seatOne: Chips(rawValue: 20)!,
        ]
        coordinatedCorruption.uncalledReturns = [
            seatZero: Chips(rawValue: 30)!,
            seatOne: Chips(rawValue: 10)!,
        ]
        coordinatedCorruption.settledPots = [
            Pot(amount: Chips(rawValue: 40)!, eligible: [seatOne]),
        ]
        coordinatedCorruption.awards = [seatOne: Chips(rawValue: 40)!]
        coordinatedCorruption.seats[0].stack = Chips(rawValue: 980)!
        coordinatedCorruption.seats[1].stack = Chips(rawValue: 50)!
        #expect(throws: PokerRuleError.invalidState("settlement contribution mismatch")) {
            try StateValidator.validate(coordinatedCorruption)
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
        #expect(first.summaries.count == 500)
        #expect(second.summaries.count == 500)
        #expect(first.seededCoverage == second.seededCoverage)
        #expect(first.fixedScenarioCoverage == second.fixedScenarioCoverage)
        try first.seededCoverage.requireMinimums(label: "500 seeded hands")
        try first.fixedScenarioCoverage.requireMinimums(label: "fixed legal scenarios")

        for (firstSummary, secondSummary) in zip(first.summaries, second.summaries) {
            guard firstSummary.seed == secondSummary.seed,
                  firstSummary.playerCount == secondSummary.playerCount,
                  firstSummary == secondSummary else {
                let details = [
                    "determinism mismatch seed=\(firstSummary.seed)",
                    "playerCount=\(firstSummary.playerCount)",
                    "firstActions=\(firstSummary.actions)",
                    "secondActions=\(secondSummary.actions)",
                    "firstEvents=\(firstSummary.events)",
                    "secondEvents=\(secondSummary.events)",
                ].joined(separator: ", ")
                Issue.record(Comment(rawValue: details))
                throw PokerRuleError.invalidState("simulation determinism mismatch")
            }
        }
        print("StatePropertyTests seeded coverage (500 seeds): \(first.seededCoverage)")
        print("StatePropertyTests fixed scenario coverage: \(first.fixedScenarioCoverage)")
    }

    private func runBatch() throws -> SimulationBatch {
        var summaries: [SimulationSummary] = []
        var seededCoverage = SimulationCoverage()
        for seed in 1...500 {
            let playerCount = 2 + seed % 8
            var reproducedActions: [RecordedAction] = []
            do {
                let result = try Simulation.playLegalHand(
                    seed: UInt64(seed),
                    playerCount: playerCount
                )
                reproducedActions = result.actions
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
                try result.validateAudit()
                try seededCoverage.observe(result.state)
                summaries.append(result.summary)
            } catch {
                let details = "seed=\(seed), playerCount=\(playerCount), "
                    + "actions=\(reproducedActions), error=\(error)"
                Issue.record(Comment(rawValue: details))
                throw error
            }
        }

        var fixedScenarioCoverage = SimulationCoverage()
        try fixedScenarioCoverage.observe(Fixtures.resolveThreeWayAllInWithTwoSidePots().state)
        try fixedScenarioCoverage.observe(Fixtures.resolveBoardPlayingTie().state)
        try fixedScenarioCoverage.observe(shortBigBlindCompletion(seed: 201))
        return SimulationBatch(
            summaries: summaries,
            seededCoverage: seededCoverage,
            fixedScenarioCoverage: fixedScenarioCoverage
        )
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

    private func shortBigBlindCompletion(seed: UInt64) throws -> HoldemState {
        let started = try HoldemEngine.start(
            config: Fixtures.standardConfig(dealer: 0),
            stacks: [
                SeatID(rawValue: 0)!: Chips(rawValue: 1_000)!,
                SeatID(rawValue: 1)!: Chips(rawValue: 30)!,
            ],
            seed: seed
        )
        let showdown = try HoldemEngine.applying(
            .fold,
            by: SeatID(rawValue: 0)!,
            to: started.state
        ).state
        return try HoldemEngine.advanceIfRoundComplete(showdown).state
    }
}

private struct SimulationResult {
    let seed: UInt64
    let playerCount: Int
    let state: HoldemState
    let initialTotalChips: Int
    let actions: [RecordedAction]
    let events: [GameEvent]

    var allDealtCards: [Card] {
        state.seats.flatMap(\.holeCards) + state.communityCards
    }

    var summary: SimulationSummary {
        SimulationSummary(
            seed: seed,
            playerCount: playerCount,
            state: state,
            actions: actions,
            events: events
        )
    }

    func validateAudit() throws {
        let context = "seed=\(seed), playerCount=\(playerCount), actions=\(actions)"
        #expect(events.first == .handStarted(seed: seed), "seed=\(seed), actions=\(actions)")
        #expect(events.last == .handCompleted, "seed=\(seed), actions=\(actions)")
        #expect(
            events.filter { $0 == .handCompleted }.count == 1,
            "seed=\(seed), actions=\(actions)"
        )

        let recordedEvents = events.compactMap { event -> (SeatID, PlayerAction)? in
            guard case let .actionApplied(seat, action) = event else { return nil }
            return (seat, action)
        }
        #expect(
            zip(recordedEvents, actions).allSatisfy {
                $0.0 == $1.seat && $0.1 == $1.action
            }
                && recordedEvents.count == actions.count,
            "seed=\(seed), playerCount=\(playerCount)"
        )
        guard state.actionHistory == actions else {
            Issue.record("actionHistory mismatch \(context), actual=\(state.actionHistory)")
            throw PokerRuleError.invalidState("simulation action history mismatch")
        }

        let expectedSettlement = try SettlementOracle.events(for: state)
        guard let settlementStart = events.firstIndex(where: SettlementOracle.isSettlementEvent)
        else {
            Issue.record("settlement events missing \(context), events=\(events)")
            throw PokerRuleError.invalidState("simulation settlement events missing")
        }
        let actualSettlement = Array(events[settlementStart...])
        guard actualSettlement == expectedSettlement else {
            let details = [
                "settlement audit mismatch \(context)",
                "expected=\(expectedSettlement)",
                "actual=\(actualSettlement)",
            ].joined(separator: ", ")
            Issue.record(Comment(rawValue: details))
            throw PokerRuleError.invalidState("simulation settlement audit mismatch")
        }
    }
}

private struct SimulationSummary: Equatable {
    let seed: UInt64
    let playerCount: Int
    let state: HoldemState
    let actions: [RecordedAction]
    let events: [GameEvent]
}

private struct SimulationBatch {
    let summaries: [SimulationSummary]
    let seededCoverage: SimulationCoverage
    let fixedScenarioCoverage: SimulationCoverage
}

private struct SimulationCoverage: Equatable, CustomStringConvertible {
    var multiPotHands = 0
    var differingEligibilityHands = 0
    var uncalledReturnHands = 0
    var tiedPots = 0
    var oddChipPots = 0

    var description: String {
        "multiPotHands=\(multiPotHands), "
            + "differingEligibilityHands=\(differingEligibilityHands), "
            + "uncalledReturnHands=\(uncalledReturnHands), "
            + "tiedPots=\(tiedPots), oddChipPots=\(oddChipPots)"
    }

    mutating func observe(_ state: HoldemState) throws {
        if state.settledPots.count > 1 { multiPotHands += 1 }
        if Set(state.settledPots.map(\.eligible)).count > 1 {
            differingEligibilityHands += 1
        }
        if !state.uncalledReturns.isEmpty { uncalledReturnHands += 1 }
        for award in try SettlementOracle.potAwards(for: state) {
            if award.winners.count > 1 {
                tiedPots += 1
                if award.pot.amount.rawValue % award.winners.count != 0 {
                    oddChipPots += 1
                }
            }
        }
    }

    func requireMinimums(label: String) throws {
        guard multiPotHands > 0,
              differingEligibilityHands > 0,
              uncalledReturnHands > 0,
              tiedPots > 0,
              oddChipPots > 0 else {
            Issue.record("insufficient \(label) coverage: \(self)")
            throw PokerRuleError.invalidState("insufficient simulation coverage")
        }
    }
}

private enum SettlementOracle {
    struct PotAward {
        let pot: Pot
        let winners: [SeatID]
        let amounts: [SeatID: Chips]
    }

    static func events(for state: HoldemState) throws -> [GameEvent] {
        var result: [GameEvent] = []
        for seat in state.uncalledReturns.keys.sorted() {
            guard let amount = state.uncalledReturns[seat] else {
                throw PokerRuleError.invalidState("oracle return missing")
            }
            result.append(.uncalledBetReturned(seat: seat, amount: amount))
        }
        result.append(contentsOf: state.settledPots.map(GameEvent.potCreated))
        for (index, award) in try potAwards(for: state).enumerated() {
            result.append(.potAwarded(
                potIndex: index,
                winners: award.winners,
                amounts: award.amounts
            ))
        }
        result.append(.handCompleted)
        return result
    }

    static func potAwards(for state: HoldemState) throws -> [PotAward] {
        var seatsByID: [SeatID: SeatState] = [:]
        for seat in state.seats {
            guard seatsByID.updateValue(seat, forKey: seat.id) == nil else {
                throw PokerRuleError.invalidState("oracle duplicate seat")
            }
        }

        var result: [PotAward] = []
        for pot in state.settledPots {
            guard !pot.eligible.isEmpty else {
                throw PokerRuleError.invalidState("oracle empty eligible set")
            }
            let winners: [SeatID]
            if pot.eligible.count == 1 {
                winners = Array(pot.eligible)
            } else {
                var ranked: [(SeatID, HandRank)] = []
                for seatID in pot.eligible {
                    guard let seat = seatsByID[seatID] else {
                        throw PokerRuleError.invalidState("oracle eligible seat missing")
                    }
                    ranked.append((
                        seatID,
                        try HandEvaluator.best(of: seat.holeCards + state.communityCards)
                    ))
                }
                guard let best = ranked.map(\.1).max() else {
                    throw PokerRuleError.invalidState("oracle rank missing")
                }
                winners = ranked.filter { $0.1 == best }.map(\.0)
            }
            let orderedWinners = winners.sorted {
                clockwiseDistance(from: state.dealer, to: $0)
                    < clockwiseDistance(from: state.dealer, to: $1)
            }
            let share = pot.amount.rawValue / orderedWinners.count
            let remainder = pot.amount.rawValue % orderedWinners.count
            var amounts: [SeatID: Chips] = [:]
            for (index, winner) in orderedWinners.enumerated() {
                let amount = share + (index < remainder ? 1 : 0)
                guard amounts.updateValue(Chips(rawValue: amount)!, forKey: winner) == nil else {
                    throw PokerRuleError.invalidState("oracle duplicate winner")
                }
            }
            result.append(PotAward(pot: pot, winners: orderedWinners, amounts: amounts))
        }
        return result
    }

    static func isSettlementEvent(_ event: GameEvent) -> Bool {
        switch event {
        case .uncalledBetReturned, .potCreated, .potAwarded, .handCompleted:
            return true
        default:
            return false
        }
    }

    private static func clockwiseDistance(from dealer: SeatID, to seat: SeatID) -> Int {
        let distance = (seat.rawValue - dealer.rawValue + 9) % 9
        return distance == 0 ? 9 : distance
    }
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
        var stackGenerator = SeededGenerator(seed: seed ^ 0xD1B5_4A32_D192_ED03)
        let stacks = Dictionary(uniqueKeysWithValues: (0..<playerCount).map { index in
            let tier = (Int(seed) + index) % 6
            let range: ClosedRange<Int>
            switch tier {
            case 0: range = 1...9
            case 1: range = 10...49
            case 2: range = 50...199
            case 3: range = 200...999
            case 4: range = 1_000...4_999
            default: range = 5_000...20_000
            }
            let width = UInt64(range.upperBound - range.lowerBound + 1)
            let amount = range.lowerBound + Int(stackGenerator.next() % width)
            return (SeatID(rawValue: index)!, Chips(rawValue: amount)!)
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
            seed: seed,
            playerCount: playerCount,
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
