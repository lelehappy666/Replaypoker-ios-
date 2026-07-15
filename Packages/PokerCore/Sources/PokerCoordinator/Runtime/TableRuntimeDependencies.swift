import Foundation
import PokerSession

public struct TableRuntimeDependencies: Sendable {
    public let nextHandID: @Sendable () throws -> HandID
    public let nextBusinessID: @Sendable (_ purpose: String) throws -> BusinessID
    public let nextSeed: @Sendable () -> UInt64
    public let sleep: @Sendable (_ duration: Duration) async throws -> Void

    public init(
        nextHandID: @escaping @Sendable () throws -> HandID,
        nextBusinessID: @escaping @Sendable (_ purpose: String) throws -> BusinessID,
        nextSeed: @escaping @Sendable () -> UInt64,
        sleep: @escaping @Sendable (_ duration: Duration) async throws -> Void
    ) {
        self.nextHandID = nextHandID
        self.nextBusinessID = nextBusinessID
        self.nextSeed = nextSeed
        self.sleep = sleep
    }
}

package extension TableRuntimeDependencies {
    static func immediate(seed: UInt64) -> Self {
        Self(
            nextHandID: { try HandID("hand-1") },
            nextBusinessID: { purpose in try BusinessID("\(purpose)-1") },
            nextSeed: { seed },
            sleep: { _ in }
        )
    }
}
