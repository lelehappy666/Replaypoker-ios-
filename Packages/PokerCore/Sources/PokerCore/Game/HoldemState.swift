public enum Street: Int, Codable, Sendable {
    case preflop, flop, turn, river, showdown, complete
}

public struct HandConfig: Codable, Equatable, Sendable {
    public let smallBlind: Chips
    public let bigBlind: Chips
    public let dealer: SeatID

    public init(smallBlind: Chips, bigBlind: Chips, dealer: SeatID) throws {
        let (minimumBigBlind, overflow) = smallBlind.rawValue.multipliedReportingOverflow(by: 2)
        guard !overflow else {
            throw PokerRuleError.invalidState("chip arithmetic overflow")
        }
        guard smallBlind.rawValue > 0,
              bigBlind.rawValue >= minimumBigBlind else {
            throw PokerRuleError.invalidState("invalid blinds")
        }
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.dealer = dealer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let smallBlind = try container.decode(Chips.self, forKey: .smallBlind)
        let bigBlind = try container.decode(Chips.self, forKey: .bigBlind)
        let dealer = try container.decode(SeatID.self, forKey: .dealer)

        do {
            try self.init(smallBlind: smallBlind, bigBlind: bigBlind, dealer: dealer)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid HandConfig",
                    underlyingError: error
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(smallBlind, forKey: .smallBlind)
        try container.encode(bigBlind, forKey: .bigBlind)
        try container.encode(dealer, forKey: .dealer)
    }

    private enum CodingKeys: String, CodingKey {
        case smallBlind, bigBlind, dealer
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
    public var lastActedAtBet: [SeatID: Chips]
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
        (try? checkedTotalSeatChips()) ?? Int.max
    }

    public func canAct(_ id: SeatID) -> Bool {
        seats.contains {
            $0.id == id && !$0.hasFolded && !$0.isAllIn && !$0.isSittingOut
        }
    }

    func checkedTotalSeatChips() throws -> Int {
        var total = 0
        for seat in seats {
            let (next, overflow) = total.addingReportingOverflow(seat.stack.rawValue)
            guard !overflow else {
                throw PokerRuleError.invalidState("chip arithmetic overflow")
            }
            total = next
        }
        return total
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
