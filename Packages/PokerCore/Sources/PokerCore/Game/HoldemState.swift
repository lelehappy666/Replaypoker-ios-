public enum Street: Int, Codable, Sendable {
    case preflop, flop, turn, river, showdown, complete
}

public struct HandConfig: Codable, Equatable, Sendable {
    public let smallBlind: Chips
    public let bigBlind: Chips
    public let dealer: SeatID

    public init(smallBlind: Chips, bigBlind: Chips, dealer: SeatID) throws {
        guard smallBlind.rawValue > 0,
              bigBlind.rawValue >= smallBlind.rawValue * 2 else {
            throw PokerRuleError.invalidState("invalid blinds")
        }
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.dealer = dealer
    }
}

public struct RecordedAction: Codable, Equatable, Sendable {
    public let seat: SeatID
    public let street: Street
    public let action: PlayerAction
}

public struct Pot: Codable, Equatable, Sendable {
    public let amount: Chips
    public let eligible: Set<SeatID>
}

public struct HoldemState: Codable, Equatable, Sendable {
    public var config: HandConfig
    public var deck: Deck
    public var seats: [SeatState]
    public var dealer: SeatID
    public var smallBlindSeat: SeatID
    public var bigBlindSeat: SeatID
    public var currentActor: SeatID?
    public var street: Street
    public var communityCards: [Card]
    public var currentBet: Chips
    public var lastFullRaiseSize: Chips
    public var actedSinceLastFullRaise: Set<SeatID>
    public var actionHistory: [RecordedAction]
    public var settledPots: [Pot]
    public var awards: [SeatID: Chips]
    public var unallocatedPot: Chips
    public let initialTotalChips: Int

    public var handCommitments: [SeatID: Chips] {
        Dictionary(uniqueKeysWithValues: seats.map { ($0.id, $0.committedThisHand) })
    }

    public var foldedSeats: Set<SeatID> {
        Set(seats.filter(\.hasFolded).map(\.id))
    }

    public var activeSeats: [SeatState] {
        seats.filter { !$0.hasFolded && !$0.isSittingOut }
    }

    public var dealtInSeats: [SeatState] {
        seats.filter { !$0.holeCards.isEmpty }
    }

    public var totalSeatChips: Int {
        seats.reduce(0) { $0 + $1.stack.rawValue }
    }

    public func canAct(_ id: SeatID) -> Bool {
        seats.contains {
            $0.id == id && !$0.hasFolded && !$0.isAllIn && !$0.isSittingOut
        }
    }
}

public struct LegalActionSet: Equatable, Sendable {
    public let canFold: Bool
    public let canCheck: Bool
    public let callAmount: Chips?
    public let minimumBet: Chips?
    public let minimumRaiseTo: Chips?
    public let maximumRaiseTo: Chips?
    public let canAllIn: Bool

    public var canRaise: Bool { minimumRaiseTo != nil }
}
