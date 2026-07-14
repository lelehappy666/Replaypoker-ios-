import Foundation
import PokerCore

public struct StoredHandRecord: Codable, Equatable, Sendable {
    public let id: HandID
    public let transactionID: BusinessID?
    public let sessionID: SessionID
    public let table: TableID
    public let startedAt: Date
    public let endedAt: Date
    public let localDay: LocalDay
    public let handNumber: Int
    public let record: CompletedHandRecord

    public init(
        id: HandID,
        transactionID: BusinessID? = nil,
        sessionID: SessionID,
        table: TableID,
        startedAt: Date,
        endedAt: Date,
        localDay: LocalDay,
        handNumber: Int,
        record: CompletedHandRecord
    ) {
        self.id = id
        self.transactionID = transactionID
        self.sessionID = sessionID
        self.table = table
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.localDay = localDay
        self.handNumber = handNumber
        self.record = record
    }
}

public struct PlayerStatisticsView: Codable, Equatable, Sendable {
    public let completedHands: Int
    public let wonHands: Int
    public let totalCommitted: Int
    public let netChange: Int
    public let largestWin: Int

    package init(_ statistics: PlayerStatistics) {
        completedHands = statistics.completedHands
        wonHands = statistics.wonHands
        totalCommitted = statistics.totalCommitted
        netChange = statistics.netChange
        largestWin = statistics.largestWin
    }
}

public struct HandRecordFilter: Equatable, Sendable {
    public let table: TableID?
    public let localDay: LocalDay?

    public init(table: TableID? = nil, localDay: LocalDay? = nil) {
        self.table = table
        self.localDay = localDay
    }
}

public enum DeleteAllConfirmation: Sendable {
    case confirmed
}

package enum CommandReceipt: Codable, Equatable, Sendable {
    case sitDown(request: CashTableRequest, result: CashSessionView)
    case rebuy(
        sessionID: SessionID,
        table: TableID,
        humanSeat: SeatID,
        amount: Chips,
        before: CashSessionView,
        result: CashSessionView
    )
    case zeroStackLeave(sessionID: SessionID, table: TableID)
    case cashOut(
        sessionID: SessionID,
        table: TableID,
        amount: Chips
    )
    case legacyLedgerOnly(reason: LedgerReason)
}

package struct SettlementReceipt: Codable, Equatable, Sendable {
    package let handID: HandID
    package let sessionID: SessionID
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
