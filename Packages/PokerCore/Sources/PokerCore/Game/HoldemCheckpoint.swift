package struct HoldemCheckpoint: Codable, Equatable, Sendable {
    private let state: HoldemState
    private let lastTransition: GameTransition

    init(state: HoldemState, lastTransition: GameTransition) {
        self.state = state
        self.lastTransition = lastTransition
    }

    package var config: HandConfig { state.config }

    package var startingStacks: [SeatID: Chips] { state.startingStacks }

    package var seatIDs: Set<SeatID> { Set(state.seats.map(\.id)) }

    package func restoredGame() throws -> HoldemGame {
        try StateValidator.validate(state)
        return HoldemGame(restoredState: state, lastTransition: lastTransition)
    }

    package init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let state = try values.decode(HoldemState.self, forKey: .state)
        let lastTransition = try values.decode(
            GameTransition.self,
            forKey: .lastTransition
        )

        do {
            try StateValidator.validate(state)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid Holdem checkpoint",
                    underlyingError: error
                )
            )
        }

        self.state = state
        self.lastTransition = lastTransition
    }

    private enum CodingKeys: String, CodingKey {
        case state, lastTransition
    }
}
