import Foundation
import PokerCore

public struct StoredHandRecord: Codable, Equatable, Sendable {
    public let id: HandID
    public let sessionID: SessionID
    public let table: TableID
    public let startedAt: Date
    public let endedAt: Date
    public let localDay: LocalDay
    public let handNumber: Int
    public let record: CompletedHandRecord

    public init(
        id: HandID,
        sessionID: SessionID,
        table: TableID,
        startedAt: Date,
        endedAt: Date,
        localDay: LocalDay,
        handNumber: Int,
        record: CompletedHandRecord
    ) {
        self.id = id
        self.sessionID = sessionID
        self.table = table
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.localDay = localDay
        self.handNumber = handNumber
        self.record = record
    }
}

package struct PlayerStatistics: Codable, Equatable, Sendable {
    package var completedHands: Int
    package var wonHands: Int
    package var totalCommitted: Int
    package var netChange: Int
    package var largestWin: Int

    package init(
        completedHands: Int = 0,
        wonHands: Int = 0,
        totalCommitted: Int = 0,
        netChange: Int = 0,
        largestWin: Int = 0
    ) {
        self.completedHands = completedHands
        self.wonHands = wonHands
        self.totalCommitted = totalCommitted
        self.netChange = netChange
        self.largestWin = largestWin
    }
}
