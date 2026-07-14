/// 应用层操作一局德州扑克的唯一公开入口。
///
/// 完整规则状态只保留在模块内部；调用方只能取得玩家观察、
/// 旁观观察和已完成牌局记录。
public final class HoldemGame: CustomReflectable {
    private var state: HoldemState

    private init(state: HoldemState) {
        self.state = state
    }

    public static func start(
        config: HandConfig,
        stacks: [SeatID: Chips],
        seed: UInt64
    ) throws -> HoldemGame {
        let result = try HoldemEngine.start(config: config, stacks: stacks, seed: seed)
        return HoldemGame(state: result.state)
    }

    public func apply(_ action: PlayerAction, by seat: SeatID) throws {
        state = try HoldemEngine.applying(action, by: seat, to: state).state
    }

    public func advanceIfRoundComplete() throws {
        state = try HoldemEngine.advanceIfRoundComplete(state).state
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

    public var customMirror: Mirror {
        Mirror(self, children: [(label: String?, value: Any)]())
    }
}
