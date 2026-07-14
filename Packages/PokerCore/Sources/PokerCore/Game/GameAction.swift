public enum PokerRuleError: Error, Equatable, Sendable {
    case negativeChips
    case invalidSeat
    case deckExhausted
    case invalidCards
    case insufficientPlayers
    case illegalAction(String)
    case invalidState(String)
}

public struct Chips: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public let rawValue: Int

    public init(_ value: Int) throws {
        guard value >= 0 else { throw PokerRuleError.negativeChips }
        rawValue = value
    }

    public init?(rawValue: Int) {
        guard rawValue >= 0 else { return nil }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SeatID: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public let rawValue: Int

    public init(_ value: Int) throws {
        guard (0...8).contains(value) else { throw PokerRuleError.invalidSeat }
        rawValue = value
    }

    public init?(rawValue: Int) {
        guard (0...8).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum PlayerAction: Codable, Equatable, Sendable {
    case fold
    case check
    case call
    case bet(Chips)
    case raiseTo(Chips)
    case allIn
}
