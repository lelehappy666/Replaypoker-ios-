import Foundation
import PokerCore

public struct BotObservation: Codable, Equatable, Sendable {
    public let handID: String
    public let stateVersion: Int
    public let viewer: SeatID
    public let ownHoleCards: [Card]
    public let communityCards: [Card]
    public let publicSeats: [PublicSeat]
    public let currentActor: SeatID
    public let street: Street
    public let currentBet: Chips
    public let pot: Chips
    public let legalActions: LegalActionSet
    public let actions: [RecordedAction]

    public init(
        handID: String,
        stateVersion: Int,
        observation: PlayerObservation
    ) throws {
        guard !handID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              stateVersion >= 0,
              observation.currentActor == observation.viewer,
              let currentActor = observation.currentActor,
              let legalActions = observation.legalActions
        else {
            throw BotError.invalidObservation
        }

        var potValue = 0
        for seat in observation.publicSeats {
            let (next, overflow) = potValue.addingReportingOverflow(
                seat.committedThisHand.rawValue
            )
            guard !overflow else { throw BotError.invalidObservation }
            potValue = next
        }
        guard let pot = Chips(rawValue: potValue) else {
            throw BotError.invalidObservation
        }

        self.handID = handID
        self.stateVersion = stateVersion
        viewer = observation.viewer
        ownHoleCards = observation.ownHoleCards
        communityCards = observation.communityCards
        publicSeats = observation.publicSeats
        self.currentActor = currentActor
        street = observation.street
        currentBet = observation.currentBet
        self.pot = pot
        self.legalActions = legalActions
        actions = observation.actions
    }
}
