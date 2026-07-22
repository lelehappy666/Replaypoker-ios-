import PokerCore

package struct TournamentSession: Codable, Equatable, Sendable {
    package let id: TournamentID
    package private(set) var phase: TournamentPhase
    package let blindLevels: [BlindLevel]
    package private(set) var blindLevelIndex: Int
    package private(set) var stacks: [SeatID: Chips]
    package private(set) var ranking: [SeatID]
    package let humanSeat: SeatID

    package init(
        id: TournamentID,
        phase: TournamentPhase,
        blindLevels: [BlindLevel],
        blindLevelIndex: Int = 0,
        stacks: [SeatID: Chips],
        ranking: [SeatID] = [],
        humanSeat: SeatID
    ) throws {
        self.id = id
        self.phase = phase
        self.blindLevels = blindLevels
        self.blindLevelIndex = blindLevelIndex
        self.stacks = stacks
        self.ranking = ranking
        self.humanSeat = humanSeat
        try validate()
    }

    package var view: TournamentSessionView {
        TournamentSessionView(
            id: id,
            phase: phase,
            blindLevels: blindLevels,
            blindLevelIndex: blindLevelIndex,
            stacks: stacks,
            ranking: ranking,
            humanSeat: humanSeat
        )
    }

    package func validate() throws {
        let seats = Set(stacks.keys)
        let rankedSeats = Set(ranking)
        guard stacks.count == 9,
              stacks[humanSeat] != nil,
              !blindLevels.isEmpty,
              blindLevels.allSatisfy(\.isValid),
              blindLevels.indices.contains(blindLevelIndex),
              rankedSeats.count == ranking.count,
              rankedSeats.isSubset(of: seats),
              ranking.count < stacks.count
        else {
            throw PokerSessionError.corruptSnapshot
        }
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let storage = try container.decode(Storage.self)
        try self.init(
            id: storage.id,
            phase: storage.phase,
            blindLevels: storage.blindLevels,
            blindLevelIndex: storage.blindLevelIndex,
            stacks: storage.stacks,
            ranking: storage.ranking,
            humanSeat: storage.humanSeat
        )
    }

    package func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.singleValueContainer()
        try container.encode(Storage(self))
    }

    private struct Storage: Codable {
        let id: TournamentID
        let phase: TournamentPhase
        let blindLevels: [BlindLevel]
        let blindLevelIndex: Int
        let stacks: [SeatID: Chips]
        let ranking: [SeatID]
        let humanSeat: SeatID

        init(_ session: TournamentSession) {
            id = session.id
            phase = session.phase
            blindLevels = session.blindLevels
            blindLevelIndex = session.blindLevelIndex
            stacks = session.stacks
            ranking = session.ranking
            humanSeat = session.humanSeat
        }
    }
}
