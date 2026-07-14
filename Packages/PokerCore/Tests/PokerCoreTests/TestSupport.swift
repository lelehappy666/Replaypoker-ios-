@testable import PokerCore

enum Cards {
    static func parse(_ value: String) throws -> [Card] {
        try value.split(separator: " ").map { token in
            guard token.count == 2 else { throw PokerRuleError.invalidCards }

            let characters = Array(token)
            let rank: Rank
            switch characters[0] {
            case "2": rank = .two
            case "3": rank = .three
            case "4": rank = .four
            case "5": rank = .five
            case "6": rank = .six
            case "7": rank = .seven
            case "8": rank = .eight
            case "9": rank = .nine
            case "T": rank = .ten
            case "J": rank = .jack
            case "Q": rank = .queen
            case "K": rank = .king
            case "A": rank = .ace
            default: throw PokerRuleError.invalidCards
            }

            let suit: Suit
            switch characters[1] {
            case "c": suit = .clubs
            case "d": suit = .diamonds
            case "h": suit = .hearts
            case "s": suit = .spades
            default: throw PokerRuleError.invalidCards
            }

            return Card(rank: rank, suit: suit)
        }
    }
}

enum Fixtures {
    static func tiedRanks(_ seats: [Int]) throws -> [SeatID: HandRank] {
        let rank = HandRank(category: .onePair, tieBreak: [14, 13, 12, 11])
        return try Dictionary(uniqueKeysWithValues: seats.map {
            (try SeatID($0), rank)
        })
    }

    static func nineStacks(_ amount: Int) -> [SeatID: Chips] {
        stacks(count: 9, amount: amount)
    }

    static func twoStacks(_ amount: Int) -> [SeatID: Chips] {
        stacks(count: 2, amount: amount)
    }

    static func completePreflopState() throws -> HoldemState {
        let config = try HandConfig(
            smallBlind: Chips(50),
            bigBlind: Chips(100),
            dealer: SeatID(0)
        )
        let started = try HoldemEngine.start(
            config: config,
            stacks: twoStacks(10_000),
            seed: 1
        )
        let called = try HoldemEngine.applying(
            .call,
            by: SeatID(0),
            to: started.state
        )
        return try BettingRules.applying(
            .check,
            by: SeatID(1),
            to: called.state
        )
    }

    private static func stacks(count: Int, amount: Int) -> [SeatID: Chips] {
        Dictionary(uniqueKeysWithValues: (0..<count).map {
            (SeatID(rawValue: $0)!, Chips(rawValue: amount)!)
        })
    }

    static func bettingState(
        currentBet: Int,
        seatCommitment: Int,
        stack: Int,
        lastFullRaise: Int
    ) -> HoldemState {
        let dealer = SeatID(rawValue: 8)!
        var deck = Deck.shuffled(seed: 4)
        let seats = (0...8).map { rawValue in
            let commitment = rawValue == 0
                ? seatCommitment
                : (rawValue == 2 ? currentBet : 0)
            let seatStack = rawValue == 0 ? stack : 1_000 - commitment
            return SeatState(
                id: SeatID(rawValue: rawValue)!,
                stack: Chips(rawValue: seatStack)!,
                committedThisStreet: Chips(rawValue: commitment)!,
                committedThisHand: Chips(rawValue: commitment)!,
                holeCards: [try! deck.draw(), try! deck.draw()],
                hasFolded: false,
                isAllIn: false,
                isSittingOut: false
            )
        }

        return HoldemState(
            config: try! HandConfig(
                smallBlind: Chips(rawValue: 50)!,
                bigBlind: Chips(rawValue: 100)!,
                dealer: dealer
            ),
            deck: deck,
            seats: seats,
            dealer: dealer,
            smallBlindSeat: SeatID(rawValue: 0)!,
            bigBlindSeat: SeatID(rawValue: 1)!,
            currentActor: SeatID(rawValue: 0)!,
            street: .flop,
            communityCards: [],
            currentBet: Chips(rawValue: currentBet)!,
            forcedBringIn: Chips(rawValue: 0)!,
            lastFullRaiseSize: Chips(rawValue: lastFullRaise)!,
            actedSinceLastFullRaise: [],
            lastActedAtBet: [:],
            actionHistory: [],
            settledPots: [],
            awards: [:],
            unallocatedPot: Chips(rawValue: seats.reduce(0) {
                $0 + $1.committedThisHand.rawValue
            })!,
            initialTotalChips: seats.reduce(0) {
                $0 + $1.stack.rawValue + $1.committedThisHand.rawValue
            }
        )
    }

    static func shortAllInAfterFullRaise() -> HoldemState {
        var state = bettingState(
            currentBet: 300,
            seatCommitment: 300,
            stack: 1_000,
            lastFullRaise: 200
        )
        state.currentActor = SeatID(rawValue: 1)!
        state.actedSinceLastFullRaise = [SeatID(rawValue: 0)!]
        state.lastActedAtBet = [SeatID(rawValue: 0)!: Chips(rawValue: 300)!]
        state.seats[1].stack = Chips(rawValue: 350)!
        state.seats[3].stack = Chips(rawValue: 1_650)!
        let result = try! BettingRules.applying(.allIn, by: SeatID(rawValue: 1)!, to: state)
        var returned = result
        returned.currentActor = SeatID(rawValue: 0)!
        return returned
    }
}

extension Dictionary where Key == Int, Value == Int {
    var seatMap: [SeatID: Int] {
        get throws {
            var result: [SeatID: Int] = [:]
            for (key, value) in self {
                result[try SeatID(key)] = value
            }
            return result
        }
    }
}

extension Dictionary where Key == SeatID, Value == Int {
    var chips: [SeatID: Chips] {
        get throws {
            try mapValues(Chips.init)
        }
    }
}

extension Array where Element == Int {
    var seatSet: Set<SeatID> {
        get throws {
            try Set(map(SeatID.init))
        }
    }
}
