import Foundation
import PokerCore

public struct HandArchiveMetadata: Codable, Equatable, Sendable {
    public let tableDisplayName: String
    public let humanSeat: SeatID
    public let seatDisplayNames: [SeatID: String]
    public let seatAvatarAssetNames: [SeatID: String?]?

    public init(
        tableDisplayName: String,
        humanSeat: SeatID,
        seatDisplayNames: [SeatID: String],
        seatAvatarAssetNames: [SeatID: String?]? = nil
    ) throws {
        let tableName = tableDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tableName.isEmpty,
              seatDisplayNames.count == 9,
              seatDisplayNames[humanSeat] != nil
        else {
            throw PokerSessionError.invalidTable
        }

        var names: [SeatID: String] = [:]
        for (seat, displayName) in seatDisplayNames {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw PokerSessionError.invalidTable
            }
            names[seat] = name
        }
        self.tableDisplayName = tableName
        self.humanSeat = humanSeat
        self.seatDisplayNames = names
        if let seatAvatarAssetNames {
            guard Set(seatAvatarAssetNames.keys) == Set(names.keys) else {
                throw PokerSessionError.invalidTable
            }
            self.seatAvatarAssetNames = Dictionary(
                uniqueKeysWithValues: try names.keys.map { seat in
                    let avatar = seatAvatarAssetNames[seat] ?? nil
                    let trimmed = avatar?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    guard trimmed != "" else {
                        throw PokerSessionError.invalidTable
                    }
                    return (seat, trimmed)
                }
            )
        } else {
            self.seatAvatarAssetNames = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case tableDisplayName
        case humanSeat
        case seatDisplayNames
        case seatAvatarAssetNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                tableDisplayName: container.decode(String.self, forKey: .tableDisplayName),
                humanSeat: container.decode(SeatID.self, forKey: .humanSeat),
                seatDisplayNames: container.decode(
                    [SeatID: String].self,
                    forKey: .seatDisplayNames
                ),
                seatAvatarAssetNames: container.decodeIfPresent(
                    [SeatID: String?].self,
                    forKey: .seatAvatarAssetNames
                )
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .seatDisplayNames,
                in: container,
                debugDescription: "Invalid hand archive metadata"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tableDisplayName, forKey: .tableDisplayName)
        try container.encode(humanSeat, forKey: .humanSeat)
        try container.encode(seatDisplayNames, forKey: .seatDisplayNames)
        try container.encodeIfPresent(
            seatAvatarAssetNames,
            forKey: .seatAvatarAssetNames
        )
    }
}

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
    public let archiveMetadata: HandArchiveMetadata?

    public init(
        id: HandID,
        transactionID: BusinessID? = nil,
        sessionID: SessionID,
        table: TableID,
        startedAt: Date,
        endedAt: Date,
        localDay: LocalDay,
        handNumber: Int,
        record: CompletedHandRecord,
        archiveMetadata: HandArchiveMetadata? = nil
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
        self.archiveMetadata = archiveMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case transactionID
        case sessionID
        case table
        case startedAt
        case endedAt
        case localDay
        case handNumber
        case record
        case archiveMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(HandID.self, forKey: .id)
        transactionID = try container.decodeIfPresent(BusinessID.self, forKey: .transactionID)
        sessionID = try container.decode(SessionID.self, forKey: .sessionID)
        table = try container.decode(TableID.self, forKey: .table)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        localDay = try container.decode(LocalDay.self, forKey: .localDay)
        handNumber = try container.decode(Int.self, forKey: .handNumber)
        record = try container.decode(CompletedHandRecord.self, forKey: .record)
        archiveMetadata = try container.decodeIfPresent(
            HandArchiveMetadata.self,
            forKey: .archiveMetadata
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(transactionID, forKey: .transactionID)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(table, forKey: .table)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(localDay, forKey: .localDay)
        try container.encode(handNumber, forKey: .handNumber)
        try container.encode(record, forKey: .record)
        try container.encodeIfPresent(archiveMetadata, forKey: .archiveMetadata)
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
    public let dateRange: HandRecordDateRange?

    public init(table: TableID? = nil, localDay: LocalDay? = nil) {
        self.table = table
        self.localDay = localDay
        dateRange = nil
    }

    public init(table: TableID? = nil, dateRange: HandRecordDateRange) {
        self.table = table
        localDay = nil
        self.dateRange = dateRange
    }
}

public struct HandRecordDateRange: Equatable, Sendable {
    public let first: LocalDay
    public let last: LocalDay

    public init(first: LocalDay, last: LocalDay) throws {
        guard first.rawValue <= last.rawValue else {
            throw PokerSessionError.invalidIdentifier
        }
        self.first = first
        self.last = last
    }

    public func contains(_ day: LocalDay) -> Bool {
        first.rawValue <= day.rawValue && day.rawValue <= last.rawValue
    }
}

public enum DeleteAllConfirmation: Sendable {
    case confirmed
}

package enum LegacyCashBuyInKind: String, Codable, Equatable, Sendable {
    case sitDown
    case rebuy
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
    case legacyCashBuyIn(
        kind: LegacyCashBuyInKind,
        table: TableID,
        amount: Chips,
        belongsToOpenSession: Bool
    )
    case legacyCashOut(reason: LedgerReason)
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
