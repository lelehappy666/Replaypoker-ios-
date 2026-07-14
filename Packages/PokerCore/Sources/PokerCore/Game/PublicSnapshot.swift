/// 牌桌上可被所有参与者安全查看的座位状态。
///
/// 此类型刻意不保存底牌，防止机器人或旁观接口取得隐藏信息。
public struct PublicSeat: Codable, Equatable, Sendable {
    public let id: SeatID
    public let stack: Chips
    public let committedThisStreet: Chips
    public let committedThisHand: Chips
    public let hasFolded: Bool
    public let isAllIn: Bool
    public let isSittingOut: Bool

    init(_ seat: SeatState) {
        id = seat.id
        stack = seat.stack
        committedThisStreet = seat.committedThisStreet
        committedThisHand = seat.committedThisHand
        hasFolded = seat.hasFolded
        isAllIn = seat.isAllIn
        isSittingOut = seat.isSittingOut
    }
}

/// 指定玩家能够取得的安全牌局观察。
///
/// 类型中只有查看者自己的底牌；不包含牌堆、洗牌种子或对手底牌。
public struct PlayerObservation: Codable, Equatable, Sendable {
    public let viewer: SeatID
    public let ownHoleCards: [Card]
    public let communityCards: [Card]
    public let publicSeats: [PublicSeat]
    public let currentActor: SeatID?
    public let street: Street
    public let currentBet: Chips
    public let legalActions: LegalActionSet?
    public let actions: [RecordedAction]

    init(state: HoldemState, viewer: SeatID) throws {
        guard let seat = state.seats.first(where: { $0.id == viewer }) else {
            throw PokerRuleError.invalidSeat
        }

        self.viewer = viewer
        ownHoleCards = seat.holeCards
        communityCards = state.communityCards
        publicSeats = state.seats.map(PublicSeat.init)
        currentActor = state.currentActor
        street = state.street
        currentBet = state.currentBet
        legalActions = state.currentActor == viewer
            ? try BettingRules.legalActions(for: viewer, in: state)
            : nil
        actions = state.actionHistory
    }
}

/// 不暴露任何玩家底牌的旁观者牌局观察。
public struct SpectatorObservation: Codable, Equatable, Sendable {
    public let communityCards: [Card]
    public let publicSeats: [PublicSeat]
    public let currentActor: SeatID?
    public let street: Street
    public let currentBet: Chips
    public let actions: [RecordedAction]

    init(state: HoldemState) {
        communityCards = state.communityCards
        publicSeats = state.seats.map(PublicSeat.init)
        currentActor = state.currentActor
        street = state.street
        currentBet = state.currentBet
        actions = state.actionHistory
    }
}

/// 仅能在牌局完成后生成的永久、可审计牌局记录。
///
/// 该记录是唯一包含所有实际获发底牌玩家最终底牌的公开接口。
public struct CompletedHandRecord: Codable, Equatable, Sendable {
    public let config: HandConfig
    public let holeCardsBySeat: [SeatID: [Card]]
    public let communityCards: [Card]
    public let actions: [RecordedAction]
    public let pots: [Pot]
    public let awards: [SeatID: Chips]
    public let uncalledReturns: [SeatID: Chips]
    public let startingStacks: [SeatID: Chips]
    public let settledCommitments: [SeatID: Chips]
    public let settledContributions: [SeatID: Chips]
    public let initialTotalChips: Int
    public let handRanksBySeat: [SeatID: HandRank]
    public let finalStacks: [SeatID: Chips]
    public let chipDeltas: [SeatID: Int]

    init(state: HoldemState) throws {
        guard state.street == .complete else {
            throw PokerRuleError.illegalAction("hand not complete")
        }
        try StateValidator.validate(state)

        let finalStacks = Dictionary(uniqueKeysWithValues: state.seats.map {
            ($0.id, $0.stack)
        })
        guard finalStacks.keys == state.startingStacks.keys else {
            throw PokerRuleError.invalidState("record stack mismatch")
        }
        var chipDeltas: [SeatID: Int] = [:]
        for (seat, startingStack) in state.startingStacks {
            guard let finalStack = finalStacks[seat] else {
                throw PokerRuleError.invalidState("record stack mismatch")
            }
            let (delta, overflow) = finalStack.rawValue.subtractingReportingOverflow(
                startingStack.rawValue
            )
            guard !overflow else {
                throw PokerRuleError.invalidState("chip arithmetic overflow")
            }
            chipDeltas[seat] = delta
        }

        let handRanksBySeat: [SeatID: HandRank]
        if state.communityCards.count == 5 {
            handRanksBySeat = try Dictionary(uniqueKeysWithValues: state.dealtInSeats.map {
                ($0.id, try HandEvaluator.best(of: $0.holeCards + state.communityCards))
            })
        } else {
            handRanksBySeat = [:]
        }

        config = state.config
        holeCardsBySeat = Dictionary(uniqueKeysWithValues: state.dealtInSeats.map {
            ($0.id, $0.holeCards)
        })
        communityCards = state.communityCards
        actions = state.actionHistory
        pots = state.settledPots
        awards = state.awards
        uncalledReturns = state.uncalledReturns
        startingStacks = state.startingStacks
        settledCommitments = state.settledCommitments
        settledContributions = state.settledContributions
        initialTotalChips = state.initialTotalChips
        self.handRanksBySeat = handRanksBySeat
        self.finalStacks = finalStacks
        self.chipDeltas = chipDeltas
    }
}
