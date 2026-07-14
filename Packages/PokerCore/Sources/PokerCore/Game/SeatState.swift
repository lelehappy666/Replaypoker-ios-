struct SeatState: Codable, Equatable, Sendable {
    public let id: SeatID
    public var stack: Chips
    public var committedThisStreet: Chips
    public var committedThisHand: Chips
    public var holeCards: [Card]
    public var hasFolded: Bool
    public var isAllIn: Bool
    public var isSittingOut: Bool
}
