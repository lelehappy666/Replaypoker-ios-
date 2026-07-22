import Foundation
import PokerCore

public struct TournamentID: SessionIdentifier {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PokerSessionError.invalidIdentifier }
        self.rawValue = value
    }
}

public enum TournamentPhase: String, Codable, Equatable, Sendable {
    case registered
    case active
    case eliminated
    case prizePending
    case finished
}

public struct BlindLevel: Codable, Equatable, Sendable {
    public let smallBlind: Chips
    public let bigBlind: Chips
    public let duration: Duration

    public init(
        smallBlind: Chips,
        bigBlind: Chips,
        duration: Duration
    ) {
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.duration = duration
    }

    package var isValid: Bool {
        smallBlind.rawValue > 0
            && smallBlind.rawValue <= Int.max / 2
            && bigBlind.rawValue >= smallBlind.rawValue * 2
            && duration > .zero
    }
}

public struct TournamentSessionView: Codable, Equatable, Sendable {
    public let id: TournamentID
    public let phase: TournamentPhase
    public let entryFee: Chips
    public let blindLevels: [BlindLevel]
    public let blindLevelIndex: Int
    public let stacks: [SeatID: Chips]
    public let ranking: [SeatID]
    public let humanSeat: SeatID

    public var currentBlindLevel: BlindLevel {
        blindLevels[blindLevelIndex]
    }

    public var humanRank: Int? {
        guard let index = ranking.firstIndex(of: humanSeat) else { return nil }
        return stacks.count - index
    }
}

public struct TournamentRegistrationRequest: Codable, Equatable, Sendable {
    public let id: TournamentID
    public let entryFee: Chips
    public let blindLevels: [BlindLevel]
    public let humanSeat: SeatID
    public let stacks: [SeatID: Chips]

    public init(
        id: TournamentID,
        entryFee: Chips,
        blindLevels: [BlindLevel],
        humanSeat: SeatID,
        stacks: [SeatID: Chips]
    ) {
        self.id = id
        self.entryFee = entryFee
        self.blindLevels = blindLevels
        self.humanSeat = humanSeat
        self.stacks = stacks
    }
}
