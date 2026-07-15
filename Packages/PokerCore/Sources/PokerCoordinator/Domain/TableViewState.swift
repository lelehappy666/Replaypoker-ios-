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

    public init(id: SeatID, displayName: String) throws {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PokerCoordinatorError.missingObservation }
        self.id = id
        self.displayName = name
    }
}

public struct TableSeatState: Codable, Equatable, Identifiable, Sendable {
    public let id: SeatID
    public let displayName: String
    public let stack: Chips
    public let committedThisStreet: Chips
    public let hasFolded: Bool
    public let isAllIn: Bool
    public let isDealer: Bool
    public let isCurrentActor: Bool
    public let cards: [TableCardState]
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
    case saveFailed
    case suspended
}
