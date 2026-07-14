import Foundation

package struct PersistedAppState: Codable, Equatable, Sendable {
    package static let currentVersion = 1

    package var version: Int
    package var ledger: EntertainmentChipLedger
    package var activeCashSession: CashGameSession?
    package var records: [HandID: StoredHandRecord]
    package var recordOrder: [HandID]
    package var statistics: PlayerStatistics

    package init(
        version: Int = currentVersion,
        ledger: EntertainmentChipLedger = EntertainmentChipLedger(),
        activeCashSession: CashGameSession? = nil,
        records: [HandID: StoredHandRecord] = [:],
        recordOrder: [HandID] = [],
        statistics: PlayerStatistics = PlayerStatistics()
    ) {
        self.version = version
        self.ledger = ledger
        self.activeCashSession = activeCashSession
        self.records = records
        self.recordOrder = recordOrder
        self.statistics = statistics
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case ledger
        case activeCashSession
        case records
        case recordOrder
        case statistics
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard decodedVersion == Self.currentVersion else {
            throw PokerSessionError.unsupportedVersion(decodedVersion)
        }

        version = decodedVersion
        ledger = try container.decode(EntertainmentChipLedger.self, forKey: .ledger)
        activeCashSession = try container.decodeIfPresent(
            CashGameSession.self,
            forKey: .activeCashSession
        )
        let encodedRecords = try container.decode(
            [String: StoredHandRecord].self,
            forKey: .records
        )
        do {
            records = try Dictionary(uniqueKeysWithValues: encodedRecords.map { key, record in
                (try HandID(key), record)
            })
        } catch {
            throw Self.corrupt(decoder, "牌局记录索引无效", underlyingError: error)
        }
        recordOrder = try container.decode([HandID].self, forKey: .recordOrder)
        statistics = try container.decode(PlayerStatistics.self, forKey: .statistics)

        do {
            try validate()
        } catch {
            throw Self.corrupt(decoder, "聚合存档不变量无效", underlyingError: error)
        }
    }

    package func encode(to encoder: Encoder) throws {
        do {
            try validate()
        } catch {
            throw EncodingError.invalidValue(
                self,
                .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "聚合存档不变量无效",
                    underlyingError: error
                )
            )
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(ledger, forKey: .ledger)
        try container.encodeIfPresent(activeCashSession, forKey: .activeCashSession)
        try container.encode(
            Dictionary(uniqueKeysWithValues: records.map { ($0.key.rawValue, $0.value) }),
            forKey: .records
        )
        try container.encode(recordOrder, forKey: .recordOrder)
        try container.encode(statistics, forKey: .statistics)
    }

    private func validate() throws {
        guard version == Self.currentVersion else {
            throw PokerSessionError.unsupportedVersion(version)
        }

        for (key, storedRecord) in records {
            guard key == storedRecord.id,
                  storedRecord.handNumber > 0,
                  storedRecord.startedAt <= storedRecord.endedAt
            else {
                throw PokerSessionError.corruptSnapshot
            }
        }

        let orderedKeys = Set(recordOrder)
        guard orderedKeys.count == recordOrder.count,
              orderedKeys == Set(records.keys)
        else {
            throw PokerSessionError.corruptSnapshot
        }

        guard statistics.completedHands >= 0,
              statistics.wonHands >= 0,
              statistics.wonHands <= statistics.completedHands,
              statistics.totalCommitted >= 0,
              statistics.largestWin >= 0,
              statistics.netChange >= 0
                || statistics.netChange >= -statistics.totalCommitted
        else {
            throw PokerSessionError.corruptSnapshot
        }
    }

    private static func corrupt(
        _ decoder: Decoder,
        _ description: String,
        underlyingError: Error
    ) -> DecodingError {
        .dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: description,
                underlyingError: underlyingError
            )
        )
    }
}

package protocol SessionRepository {
    func load() throws -> PersistedAppState
    func save(_ state: PersistedAppState) throws
}
