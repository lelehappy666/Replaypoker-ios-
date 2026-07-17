import Foundation
import PokerCore

public enum TableFlowPhase: String, Codable, Equatable, Sendable {
    case preparingHand, dealing, waitingForHuman, botThinking
    case animatingAction, revealingBoard, settling, savingResult
    case awaitingNextHand, saveFailed, suspended
}

public enum TableCardState: Codable, Equatable, Sendable {
    case faceDown
    case faceUp(Card)
}

public struct TableSeatProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: SeatID
    public let displayName: String
    public let avatarAssetName: String?

    public init(
        id: SeatID,
        displayName: String,
        avatarAssetName: String? = nil
    ) throws {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatar = avatarAssetName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, avatar != "" else {
            throw PokerCoordinatorError.missingObservation
        }
        self.id = id
        self.displayName = name
        self.avatarAssetName = avatar
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case avatarAssetName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(SeatID.self, forKey: .id),
            displayName: container.decode(String.self, forKey: .displayName),
            avatarAssetName: container.decodeIfPresent(
                String.self,
                forKey: .avatarAssetName
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarAssetName, forKey: .avatarAssetName)
    }
}

public struct TableSeatState: Codable, Equatable, Identifiable, Sendable {
    public let id: SeatID
    public let displayName: String
    public let avatarAssetName: String?
    public let isHuman: Bool
    public let stack: Chips
    public let committedThisStreet: Chips
    public let hasFolded: Bool
    public let isAllIn: Bool
    public let isDealer: Bool
    public let isCurrentActor: Bool
    public let cards: [TableCardState]

    public init(
        id: SeatID,
        displayName: String,
        avatarAssetName: String? = nil,
        isHuman: Bool,
        stack: Chips,
        committedThisStreet: Chips,
        hasFolded: Bool,
        isAllIn: Bool,
        isDealer: Bool,
        isCurrentActor: Bool,
        cards: [TableCardState]
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarAssetName = avatarAssetName
        self.isHuman = isHuman
        self.stack = stack
        self.committedThisStreet = committedThisStreet
        self.hasFolded = hasFolded
        self.isAllIn = isAllIn
        self.isDealer = isDealer
        self.isCurrentActor = isCurrentActor
        self.cards = cards
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case avatarAssetName
        case isHuman
        case stack
        case committedThisStreet
        case hasFolded
        case isAllIn
        case isDealer
        case isCurrentActor
        case cards
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(SeatID.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            avatarAssetName: try container.decodeIfPresent(
                String.self,
                forKey: .avatarAssetName
            ),
            isHuman: try container.decode(Bool.self, forKey: .isHuman),
            stack: try container.decode(Chips.self, forKey: .stack),
            committedThisStreet: try container.decode(
                Chips.self,
                forKey: .committedThisStreet
            ),
            hasFolded: try container.decode(Bool.self, forKey: .hasFolded),
            isAllIn: try container.decode(Bool.self, forKey: .isAllIn),
            isDealer: try container.decode(Bool.self, forKey: .isDealer),
            isCurrentActor: try container.decode(Bool.self, forKey: .isCurrentActor),
            cards: try container.decode([TableCardState].self, forKey: .cards)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarAssetName, forKey: .avatarAssetName)
        try container.encode(isHuman, forKey: .isHuman)
        try container.encode(stack, forKey: .stack)
        try container.encode(committedThisStreet, forKey: .committedThisStreet)
        try container.encode(hasFolded, forKey: .hasFolded)
        try container.encode(isAllIn, forKey: .isAllIn)
        try container.encode(isDealer, forKey: .isDealer)
        try container.encode(isCurrentActor, forKey: .isCurrentActor)
        try container.encode(cards, forKey: .cards)
    }
}

public enum TableMiddleAction: Codable, Equatable, Sendable {
    case check
    case call(Chips)
}

public enum TableAggressiveAction: Codable, Equatable, Sendable {
    case bet(minimum: Chips, maximum: Chips, canAllIn: Bool)
    case raise(minimum: Chips, maximum: Chips, canAllIn: Bool)
}

public struct TableActionControls: Codable, Equatable, Sendable {
    public let canFold: Bool
    public let middle: TableMiddleAction?
    public let aggressive: TableAggressiveAction?

    package init(legalActions: LegalActionSet) throws {
        canFold = legalActions.canFold
        middle = legalActions.canCheck
            ? .check
            : legalActions.callAmount.map(TableMiddleAction.call)

        if let minimum = legalActions.minimumBet,
           let maximum = legalActions.maximumRaiseTo,
           minimum <= maximum {
            aggressive = .bet(
                minimum: minimum,
                maximum: maximum,
                canAllIn: legalActions.canAllIn
            )
        } else if let minimum = legalActions.minimumRaiseTo,
                  let maximum = legalActions.maximumRaiseTo,
                  minimum <= maximum {
            aggressive = .raise(
                minimum: minimum,
                maximum: maximum,
                canAllIn: legalActions.canAllIn
            )
        } else {
            aggressive = nil
        }
    }
}

public struct TableViewState: Codable, Equatable, Sendable {
    public let handID: String?
    public let stateVersion: Int
    public let animationSequence: Int
    public let phase: TableFlowPhase
    public let seats: [TableSeatState]
    public let communityCards: [Card]
    public let pot: Chips
    public let controls: TableActionControls?
    public let secondsRemaining: Int?
    public let winners: Set<SeatID>
    public let errorMessage: String?
    public let animation: TableAnimationEvent?
}

public enum PokerCoordinatorError: Error, Equatable, Sendable {
    case invalidPhase
    case illegalIntent
    case missingObservation
    case chipArithmeticOverflow
    case animationSequenceOverflow
    case saveFailed
    case suspended
}
