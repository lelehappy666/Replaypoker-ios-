struct EngineResult: Equatable, Sendable {
    public let state: HoldemState
    public let events: [GameEvent]

    public init(state: HoldemState, events: [GameEvent]) {
        self.state = state
        self.events = events
    }
}

enum GameEvent: Equatable, Sendable {
    case handStarted(seed: UInt64)
    case blindPosted(seat: SeatID, amount: Chips)
    case holeCardsDealt(seat: SeatID)
    case actionApplied(seat: SeatID, action: PlayerAction)
    case streetChanged(Street)
    case communityCardsDealt([Card])
    /// 同一次结算的未跟注退回事件按 SeatID 升序发出，且先于底池事件。
    case uncalledBetReturned(seat: SeatID, amount: Chips)
    case potCreated(Pot)
    case potAwarded(potIndex: Int, winners: [SeatID], amounts: [SeatID: Chips])
    case handCompleted
}

/// 应用层可安全消费的牌局领域事件。
///
/// 开局事件刻意不包含洗牌种子；发底牌事件也只通知座位，
/// 不包含实际底牌。
public enum PublicGameEvent: Codable, Equatable, Sendable {
    case handStarted
    case blindPosted(seat: SeatID, amount: Chips)
    case holeCardsDealt(seat: SeatID)
    case actionApplied(seat: SeatID, action: PlayerAction)
    case streetChanged(Street)
    case communityCardsDealt([Card])
    case uncalledBetReturned(seat: SeatID, amount: Chips)
    case potCreated(Pot)
    case potAwarded(potIndex: Int, winners: [SeatID], amounts: [SeatID: Chips])
    case handCompleted

    init(_ event: GameEvent) {
        switch event {
        case .handStarted:
            self = .handStarted
        case let .blindPosted(seat, amount):
            self = .blindPosted(seat: seat, amount: amount)
        case let .holeCardsDealt(seat):
            self = .holeCardsDealt(seat: seat)
        case let .actionApplied(seat, action):
            self = .actionApplied(seat: seat, action: action)
        case let .streetChanged(street):
            self = .streetChanged(street)
        case let .communityCardsDealt(cards):
            self = .communityCardsDealt(cards)
        case let .uncalledBetReturned(seat, amount):
            self = .uncalledBetReturned(seat: seat, amount: amount)
        case let .potCreated(pot):
            self = .potCreated(pot)
        case let .potAwarded(potIndex, winners, amounts):
            self = .potAwarded(potIndex: potIndex, winners: winners, amounts: amounts)
        case .handCompleted:
            self = .handCompleted
        }
    }
}

/// 一次公开牌局操作产生的有序、安全事件集合。
public struct GameTransition: Codable, Equatable, Sendable {
    public let events: [PublicGameEvent]

    init(_ events: [GameEvent]) {
        self.events = events.map(PublicGameEvent.init)
    }
}
