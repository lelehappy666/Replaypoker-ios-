public enum HoldemEngine {
    public static func start(
        config: HandConfig,
        stacks: [SeatID: Chips],
        seed: UInt64
    ) throws -> EngineResult {
        guard stacks.count >= 2 else {
            throw PokerRuleError.insufficientPlayers
        }
        guard stacks.values.allSatisfy({ $0.rawValue > 0 }) else {
            throw PokerRuleError.invalidState("non-positive stack")
        }
        guard stacks[config.dealer] != nil else {
            throw PokerRuleError.invalidState("dealer is not seated")
        }

        let orderedIDs = stacks.keys.sorted()
        let smallBlindSeat: SeatID
        let bigBlindSeat: SeatID
        if orderedIDs.count == 2 {
            smallBlindSeat = config.dealer
            bigBlindSeat = try nextSeat(after: config.dealer, among: orderedIDs)
        } else {
            smallBlindSeat = try nextSeat(after: config.dealer, among: orderedIDs)
            bigBlindSeat = try nextSeat(after: smallBlindSeat, among: orderedIDs)
        }

        let seats = orderedIDs.map { id in
            let stack = stacks[id]!
            return SeatState(
                id: id,
                stack: stack,
                committedThisStreet: Chips(rawValue: 0)!,
                committedThisHand: Chips(rawValue: 0)!,
                holeCards: [],
                hasFolded: false,
                isAllIn: stack.rawValue == 0,
                isSittingOut: false
            )
        }
        let initialTotalChips = try checkedSum(seats.map { $0.stack.rawValue })
        var state = HoldemState(
            config: config,
            deck: Deck.shuffled(seed: seed),
            seats: seats,
            dealer: config.dealer,
            smallBlindSeat: smallBlindSeat,
            bigBlindSeat: bigBlindSeat,
            currentActor: nil,
            street: .preflop,
            communityCards: [],
            currentBet: Chips(rawValue: 0)!,
            forcedBringIn: config.bigBlind,
            lastFullRaiseSize: config.bigBlind,
            actedSinceLastFullRaise: [],
            lastActedAtBet: [:],
            actionHistory: [],
            settledPots: [],
            awards: [:],
            uncalledReturns: [:],
            startingStacks: stacks,
            settledCommitments: [:],
            settledContributions: [:],
            unallocatedPot: Chips(rawValue: 0)!,
            initialTotalChips: initialTotalChips
        )
        var events: [GameEvent] = [.handStarted(seed: seed)]

        let postedSmallBlind = try postBlind(config.smallBlind, by: smallBlindSeat, to: &state)
        events.append(.blindPosted(seat: smallBlindSeat, amount: postedSmallBlind))
        let postedBigBlind = try postBlind(config.bigBlind, by: bigBlindSeat, to: &state)
        events.append(.blindPosted(seat: bigBlindSeat, amount: postedBigBlind))
        state.currentBet = max(
            state.seats.map(\.committedThisStreet).max() ?? Chips(rawValue: 0)!,
            state.forcedBringIn
        )

        let dealingOrder = circularOrder(after: config.dealer, among: orderedIDs)
        for _ in 0..<2 {
            for id in dealingOrder {
                let card = try state.deck.draw()
                guard let index = state.seats.firstIndex(where: { $0.id == id }) else {
                    throw PokerRuleError.invalidState("dealt seat missing")
                }
                state.seats[index].holeCards.append(card)
                events.append(.holeCardsDealt(seat: id))
            }
        }

        state.currentActor = nextActor(after: bigBlindSeat, in: state)
        let advanced = try advanceIfNoActionIsPossible(state)
        events.append(contentsOf: advanced.events)
        return try validatedResult(EngineResult(state: advanced.state, events: events))
    }

    public static func applying(
        _ action: PlayerAction,
        by seat: SeatID,
        to state: HoldemState
    ) throws -> EngineResult {
        try validatePublicInput(state)
        guard [.preflop, .flop, .turn, .river].contains(state.street) else {
            throw PokerRuleError.illegalAction("hand is not accepting actions")
        }

        var result = try BettingRules.applying(action, by: seat, to: state)
        var events: [GameEvent] = [.actionApplied(seat: seat, action: action)]

        if remainingPlayers(in: result).count <= 1 {
            normalizeForTerminalStreet(&result)
            events.append(.streetChanged(.showdown))
            return try validatedResult(EngineResult(state: result, events: events))
        }

        if roundIsComplete(result) || noFurtherBettingIsPossible(result) {
            let advanced = try advanceOneStreet(result)
            events.append(contentsOf: advanced.events)
            return try validatedResult(EngineResult(state: advanced.state, events: events))
        }

        result.currentActor = nextActorNeedingAction(after: seat, in: result)
        guard result.currentActor != nil else {
            throw PokerRuleError.invalidState("betting round has no next actor")
        }
        return try validatedResult(EngineResult(state: result, events: events))
    }

    public static func advanceIfRoundComplete(_ state: HoldemState) throws -> EngineResult {
        try validatePublicInput(state)
        if state.street == .showdown {
            return try validatedResult(settle(state))
        }
        guard state.street != .complete else {
            return try validatedResult(EngineResult(state: state, events: []))
        }
        if remainingPlayers(in: state).count <= 1 {
            var result = state
            normalizeForTerminalStreet(&result)
            return try validatedResult(
                EngineResult(state: result, events: [.streetChanged(.showdown)])
            )
        }
        guard roundIsComplete(state) || noFurtherBettingIsPossible(state) else {
            return try validatedResult(EngineResult(state: state, events: []))
        }
        return try validatedResult(advanceOneStreet(state))
    }

    private static func settle(_ state: HoldemState) throws -> EngineResult {
        let activeSeats = state.activeSeats
        guard !activeSeats.isEmpty else {
            throw PokerRuleError.invalidState("showdown has no active seats")
        }
        if activeSeats.count > 1, state.communityCards.count != 5 {
            throw PokerRuleError.invalidCards
        }

        let highestActiveCommitment = activeSeats
            .map(\.committedThisHand.rawValue)
            .max()!
        let normalizedCommitments = state.handCommitments.mapValues {
            Chips(rawValue: min($0.rawValue, highestActiveCommitment))!
        }
        let uncalledReturns = Dictionary(uniqueKeysWithValues: state.handCommitments.compactMap {
            seat, commitment -> (SeatID, Chips)? in
            let amount = commitment.rawValue - normalizedCommitments[seat]!.rawValue
            return amount > 0 ? (seat, Chips(rawValue: amount)!) : nil
        })
        let pots = try PotBuilder.build(
            commitments: normalizedCommitments,
            folded: state.foldedSeats
        )
        let ranks: [SeatID: HandRank]
        if activeSeats.count == 1 {
            ranks = [
                activeSeats[0].id: HandRank(category: .highCard, tieBreak: []),
            ]
        } else {
            ranks = try Dictionary(uniqueKeysWithValues: activeSeats.map { seat in
                (
                    seat.id,
                    try HandEvaluator.best(of: seat.holeCards + state.communityCards)
                )
            })
        }

        let perPotAwards = try Dictionary(uniqueKeysWithValues: pots.enumerated().map {
            index, pot in
            (index, try PotBuilder.awards(for: [pot], ranks: ranks, dealer: state.dealer))
        })
        let awards = try aggregateAwards(perPotAwards)
        let completed = try state.completingHand(
            pots: pots,
            awards: awards,
            uncalledReturns: uncalledReturns,
            contributions: normalizedCommitments
        )
        try BettingRules.validateStructuralState(completed)

        var events = uncalledReturns.keys.sorted().map {
            GameEvent.uncalledBetReturned(seat: $0, amount: uncalledReturns[$0]!)
        }
        events.append(contentsOf: pots.map(GameEvent.potCreated))
        events.append(contentsOf: pots.indices.map { index in
            let amounts = perPotAwards[index]!
            return GameEvent.potAwarded(
                potIndex: index,
                winners: circularOrder(after: state.dealer, among: Array(amounts.keys)),
                amounts: amounts
            )
        })
        events.append(.handCompleted)
        return EngineResult(state: completed, events: events)
    }

    private static func aggregateAwards(
        _ perPotAwards: [Int: [SeatID: Chips]]
    ) throws -> [SeatID: Chips] {
        try perPotAwards.values.reduce(into: [SeatID: Chips]()) { result, awards in
            for (seat, amount) in awards {
                let total = try checkedAdd(result[seat]?.rawValue ?? 0, amount.rawValue)
                result[seat] = Chips(rawValue: total)!
            }
        }
    }

    private static func advanceOneStreet(_ state: HoldemState) throws -> EngineResult {
        var result = state
        var events: [GameEvent] = []

        switch state.street {
        case .preflop:
            try beginStreet(.flop, drawing: 3, state: &result, events: &events)
        case .flop:
            try beginStreet(.turn, drawing: 1, state: &result, events: &events)
        case .turn:
            try beginStreet(.river, drawing: 1, state: &result, events: &events)
        case .river:
            normalizeForTerminalStreet(&result)
            events.append(.streetChanged(.showdown))
            return EngineResult(state: result, events: events)
        case .showdown, .complete:
            return EngineResult(state: result, events: events)
        }

        let runout = try advanceIfNoActionIsPossible(result)
        events.append(contentsOf: runout.events)
        return EngineResult(state: runout.state, events: events)
    }

    private static func beginStreet(
        _ street: Street,
        drawing cardCount: Int,
        state: inout HoldemState,
        events: inout [GameEvent]
    ) throws {
        state.street = street
        state.currentBet = Chips(rawValue: 0)!
        state.forcedBringIn = Chips(rawValue: 0)!
        state.lastFullRaiseSize = state.config.bigBlind
        state.actedSinceLastFullRaise = []
        state.lastActedAtBet = [:]
        for index in state.seats.indices {
            state.seats[index].committedThisStreet = Chips(rawValue: 0)!
        }
        state.currentActor = nextActor(after: state.dealer, in: state)
        events.append(.streetChanged(street))

        var dealt: [Card] = []
        for _ in 0..<cardCount {
            let card = try state.deck.draw()
            state.communityCards.append(card)
            dealt.append(card)
        }
        events.append(.communityCardsDealt(dealt))
    }

    private static func advanceIfNoActionIsPossible(_ state: HoldemState) throws -> EngineResult {
        guard noFurtherBettingIsPossible(state) else {
            return EngineResult(state: state, events: [])
        }
        return try advanceOneStreet(state)
    }

    private static func noFurtherBettingIsPossible(_ state: HoldemState) -> Bool {
        guard remainingPlayers(in: state).count >= 2 else {
            return false
        }
        let actionable = actionablePlayers(in: state)
        if actionable.isEmpty {
            return true
        }
        if actionable.count == 1 {
            return actionable[0].committedThisStreet >= state.currentBet
        }
        return false
    }

    private static func normalizeForTerminalStreet(_ state: inout HoldemState) {
        state.currentActor = nil
        state.street = .showdown
        state.forcedBringIn = Chips(rawValue: 0)!
        state.currentBet = state.seats.map(\.committedThisStreet).max()
            ?? Chips(rawValue: 0)!
        state.actedSinceLastFullRaise = []
        state.lastActedAtBet = [:]
    }

    private static func roundIsComplete(_ state: HoldemState) -> Bool {
        let players = actionablePlayers(in: state)
        return players.allSatisfy {
            $0.committedThisStreet == state.currentBet
                && state.actedSinceLastFullRaise.contains($0.id)
        }
    }

    private static func actionablePlayers(in state: HoldemState) -> [SeatState] {
        state.seats.filter { state.canAct($0.id) }
    }

    private static func remainingPlayers(in state: HoldemState) -> [SeatState] {
        state.seats.filter { !$0.hasFolded && !$0.isSittingOut }
    }

    private static func nextActor(after anchor: SeatID, in state: HoldemState) -> SeatID? {
        let ids = state.seats.map(\.id)
        return circularOrder(after: anchor, among: ids).first(where: state.canAct)
    }

    private static func nextActorNeedingAction(
        after anchor: SeatID,
        in state: HoldemState
    ) -> SeatID? {
        let ids = state.seats.map(\.id)
        return circularOrder(after: anchor, among: ids).first { id in
            guard state.canAct(id),
                  let seat = state.seats.first(where: { $0.id == id }) else {
                return false
            }
            return seat.committedThisStreet < state.currentBet
                || !state.actedSinceLastFullRaise.contains(id)
        }
    }

    private static func postBlind(
        _ blind: Chips,
        by id: SeatID,
        to state: inout HoldemState
    ) throws -> Chips {
        guard let index = state.seats.firstIndex(where: { $0.id == id }) else {
            throw PokerRuleError.invalidState("blind seat missing")
        }
        let amount = min(blind.rawValue, state.seats[index].stack.rawValue)
        state.seats[index].stack = Chips(
            rawValue: state.seats[index].stack.rawValue - amount
        )!
        state.seats[index].committedThisStreet = Chips(rawValue: amount)!
        state.seats[index].committedThisHand = Chips(rawValue: amount)!
        state.seats[index].isAllIn = state.seats[index].stack.rawValue == 0
        state.unallocatedPot = Chips(
            rawValue: try checkedAdd(state.unallocatedPot.rawValue, amount)
        )!
        return Chips(rawValue: amount)!
    }

    private static func nextSeat(after anchor: SeatID, among ids: [SeatID]) throws -> SeatID {
        guard let next = circularOrder(after: anchor, among: ids).first else {
            throw PokerRuleError.invalidState("seat order is empty")
        }
        return next
    }

    private static func circularOrder(after anchor: SeatID, among ids: [SeatID]) -> [SeatID] {
        ids.sorted {
            clockwiseDistance(from: anchor, to: $0)
                < clockwiseDistance(from: anchor, to: $1)
        }
    }

    private static func clockwiseDistance(from anchor: SeatID, to id: SeatID) -> Int {
        let distance = (id.rawValue - anchor.rawValue + 9) % 9
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

    private static func validatePublicInput(_ state: HoldemState) throws {
        #if DEBUG
        try StateValidator.validate(state)
        #else
        try BettingRules.validateStructuralState(state)
        #endif
    }

    private static func validatedResult(_ result: EngineResult) throws -> EngineResult {
        #if DEBUG
        try StateValidator.validate(result.state)
        #endif
        return result
    }
}
