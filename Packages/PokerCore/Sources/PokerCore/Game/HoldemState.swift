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

struct HoldemState: Codable, Equatable, Sendable {
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
    public var forcedBringIn: Chips
    public var lastFullRaiseSize: Chips
    public var actedSinceLastFullRaise: Set<SeatID>
    public var lastActedAtBet: [SeatID: Chips]
    public var actionHistory: [RecordedAction]
    public var settledPots: [Pot]
    public var awards: [SeatID: Chips]
    public var uncalledReturns: [SeatID: Chips]
    public let startingStacks: [SeatID: Chips]
    public var settledCommitments: [SeatID: Chips]
    public var settledContributions: [SeatID: Chips]
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

    /// 仅适用于已经通过状态验证的牌局；未验证数据请调用 `validatedTotalSeatChips()`。
    public var totalSeatChips: Int {
        do {
            return try validatedTotalSeatChips()
        } catch {
            preconditionFailure("totalSeatChips requires a validated state: \(error)")
        }
    }

    public func canAct(_ id: SeatID) -> Bool {
        seats.contains {
            $0.id == id && !$0.hasFolded && !$0.isAllIn && !$0.isSittingOut
        }
    }

    public func validatedTotalSeatChips() throws -> Int {
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

    func completingHand(
        pots: [Pot],
        awards: [SeatID: Chips],
        uncalledReturns: [SeatID: Chips],
        contributions: [SeatID: Chips]
    ) throws -> HoldemState {
        var result = self

        for (seat, amount) in try merging(awards, with: uncalledReturns) {
            guard let index = result.seats.firstIndex(where: { $0.id == seat }) else {
                throw PokerRuleError.invalidState("awarded seat missing")
            }
            let (stack, overflow) = result.seats[index].stack.rawValue
                .addingReportingOverflow(amount.rawValue)
            guard !overflow else {
                throw PokerRuleError.invalidState("chip arithmetic overflow")
            }
            result.seats[index].stack = Chips(rawValue: stack)!
        }

        for index in result.seats.indices {
            result.seats[index].committedThisStreet = Chips(rawValue: 0)!
            result.seats[index].committedThisHand = Chips(rawValue: 0)!
            result.seats[index].isAllIn = result.seats[index].stack.rawValue == 0
        }
        result.currentActor = nil
        result.street = .complete
        result.currentBet = Chips(rawValue: 0)!
        result.forcedBringIn = Chips(rawValue: 0)!
        result.actedSinceLastFullRaise = []
        result.lastActedAtBet = [:]
        result.settledPots = pots
        result.awards = awards
        result.uncalledReturns = uncalledReturns
        result.settledCommitments = handCommitments
        result.settledContributions = contributions
        result.unallocatedPot = Chips(rawValue: 0)!
        return result
    }

    private func merging(
        _ lhs: [SeatID: Chips],
        with rhs: [SeatID: Chips]
    ) throws -> [SeatID: Chips] {
        try rhs.reduce(into: lhs) { result, entry in
            let (amount, overflow) = (result[entry.key]?.rawValue ?? 0)
                .addingReportingOverflow(entry.value.rawValue)
            guard !overflow else {
                throw PokerRuleError.invalidState("chip arithmetic overflow")
            }
            result[entry.key] = Chips(rawValue: amount)!
        }
    }
}

public struct LegalActionSet: Codable, Equatable, Sendable {
    public let canFold: Bool
    public let canCheck: Bool
    public let callAmount: Chips?
    public let minimumBet: Chips?
    public let minimumRaiseTo: Chips?
    public let maximumRaiseTo: Chips?
    public let canAllIn: Bool

    public var canRaise: Bool { minimumRaiseTo != nil }
}
