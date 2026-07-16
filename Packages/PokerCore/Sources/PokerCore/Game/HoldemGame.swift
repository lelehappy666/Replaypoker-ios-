/// 应用层操作一局德州扑克的唯一公开入口。
///
/// 完整规则状态只保留在模块内部；调用方只能取得玩家观察、
/// 旁观观察和已完成牌局记录。
public final class HoldemGame: CustomReflectable {
    private var state: HoldemState
    public private(set) var lastTransition: GameTransition

    private init(state: HoldemState, lastTransition: GameTransition) {
        self.state = state
        self.lastTransition = lastTransition
    }

    init(restoredState: HoldemState, lastTransition: GameTransition) {
        state = restoredState
        self.lastTransition = lastTransition
    }

    public static func start(
        config: HandConfig,
        stacks: [SeatID: Chips],
        seed: UInt64
    ) throws -> HoldemGame {
        let result = try HoldemEngine.start(config: config, stacks: stacks, seed: seed)
        return HoldemGame(
            state: result.state,
            lastTransition: GameTransition(result.events)
        )
    }

    @discardableResult
    public func apply(_ action: PlayerAction, by seat: SeatID) throws -> GameTransition {
        let result = try HoldemEngine.applying(action, by: seat, to: state)
        state = result.state
        let transition = GameTransition(result.events)
        lastTransition = transition
        return transition
    }

    @discardableResult
    package func foldForDeparture(_ seat: SeatID) throws -> GameTransition {
        let result = try HoldemEngine.foldingForDeparture(seat, in: state)
        state = result.state
        let transition = GameTransition(result.events)
        lastTransition = transition
        return transition
    }

    @discardableResult
    public func advanceIfRoundComplete() throws -> GameTransition {
        let result = try HoldemEngine.advanceIfRoundComplete(state)
        state = result.state
        let transition = GameTransition(result.events)
        lastTransition = transition
        return transition
    }

    public func playerObservation(for seat: SeatID) throws -> PlayerObservation {
        try PlayerObservation(state: state, viewer: seat)
    }

    public func spectatorObservation() -> SpectatorObservation {
        SpectatorObservation(state: state)
    }

    public func completedRecord() throws -> CompletedHandRecord {
        try CompletedHandRecord(state: state)
    }

    package func makeCheckpoint() -> HoldemCheckpoint {
        HoldemCheckpoint(state: state, lastTransition: lastTransition)
    }

    package static func restore(from checkpoint: HoldemCheckpoint) throws -> HoldemGame {
        try checkpoint.restoredGame()
    }

    public var customMirror: Mirror {
        Mirror(self, children: [(label: String?, value: Any)]())
    }
}
