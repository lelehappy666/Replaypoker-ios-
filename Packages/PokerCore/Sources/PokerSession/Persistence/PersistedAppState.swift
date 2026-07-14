import Foundation
import PokerCore

package struct PersistedAppState: Codable, Equatable, Sendable {
    package static let currentVersion = 1

    package var version: Int
    package var ledger: EntertainmentChipLedger
    package var activeCashSession: CashGameSession?
    package var records: [HandID: StoredHandRecord]
    package var recordOrder: [HandID]
    package var statistics: PlayerStatistics
    package var commandReceipts: [BusinessID: CommandReceipt]

    package init(
        version: Int = currentVersion,
        ledger: EntertainmentChipLedger = EntertainmentChipLedger(),
        activeCashSession: CashGameSession? = nil,
        records: [HandID: StoredHandRecord] = [:],
        recordOrder: [HandID] = [],
        statistics: PlayerStatistics = PlayerStatistics(),
        commandReceipts: [BusinessID: CommandReceipt] = [:]
    ) {
        self.version = version
        self.ledger = ledger
        self.activeCashSession = activeCashSession
        self.records = records
        self.recordOrder = recordOrder
        self.statistics = statistics
        self.commandReceipts = commandReceipts
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case ledger
        case activeCashSession
        case records
        case recordOrder
        case statistics
        case commandReceipts
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
        let encodedReceipts = try container.decodeIfPresent(
            [String: CommandReceipt].self,
            forKey: .commandReceipts
        ) ?? [:]
        do {
            commandReceipts = try Dictionary(
                uniqueKeysWithValues: encodedReceipts.map { key, receipt in
                    (try BusinessID(key), receipt)
                }
            )
        } catch {
            throw Self.corrupt(decoder, "业务收据索引无效", underlyingError: error)
        }

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
        try container.encode(
            Dictionary(uniqueKeysWithValues: commandReceipts.map {
                ($0.key.rawValue, $0.value)
            }),
            forKey: .commandReceipts
        )
    }

    private func validate() throws {
        guard version == Self.currentVersion else {
            throw PokerSessionError.unsupportedVersion(version)
        }

        var handNumbersBySession: [SessionID: Set<Int>] = [:]
        for (key, storedRecord) in records {
            guard key == storedRecord.id,
                  storedRecord.handNumber > 0,
                  storedRecord.startedAt <= storedRecord.endedAt,
                  handNumbersBySession[storedRecord.sessionID, default: []]
                    .insert(storedRecord.handNumber).inserted
            else {
                throw PokerSessionError.corruptSnapshot
            }
            try storedRecord.record.validateForPersistence()
        }

        let orderedKeys = Set(recordOrder)
        guard orderedKeys.count == recordOrder.count,
              orderedKeys == Set(records.keys)
        else {
            throw PokerSessionError.corruptSnapshot
        }

        guard statistics.completedHands >= 0,
              statistics.completedHands >= records.count,
              statistics.wonHands >= 0,
              statistics.wonHands <= statistics.completedHands,
              statistics.totalCommitted >= 0,
              statistics.largestWin >= 0,
              statistics.netChange >= 0
                || statistics.netChange >= -statistics.totalCommitted
        else {
            throw PokerSessionError.corruptSnapshot
        }

        let ledgerEntriesByID = Dictionary(uniqueKeysWithValues: ledger.entries.map {
            ($0.businessID, $0)
        })
        let ledgerBusinessIDs = Set(ledgerEntriesByID.keys)
        let settlementBusinessIDs = Set(records.values.compactMap(\.transactionID))
        let receiptBusinessIDs = Set(commandReceipts.keys)
        guard ledgerBusinessIDs.isDisjoint(with: settlementBusinessIDs),
              settlementBusinessIDs.isDisjoint(with: receiptBusinessIDs),
              settlementBusinessIDs.count
                == records.values.compactMap(\.transactionID).count
        else {
            throw PokerSessionError.corruptSnapshot
        }

        for (id, receipt) in commandReceipts {
            switch receipt {
            case let .sitDown(request, result):
                guard let humanStack = request.stacks[request.humanSeat],
                      let entry = ledgerEntriesByID[id],
                      let resultStacks = validatedReadyStacks(in: result),
                      entry.reason == .cashBuyIn(table: request.table),
                      entry.delta == -humanStack.rawValue,
                      result.id == request.sessionID,
                      result.table == request.table,
                      result.humanSeat == request.humanSeat,
                      result.dealer == request.config.dealer,
                      result.completedHands == 0,
                      resultStacks == request.stacks
                else {
                    throw PokerSessionError.corruptSnapshot
                }
            case let .rebuy(sessionID, table, humanSeat, amount, before, result):
                guard let entry = ledgerEntriesByID[id],
                      let beforeStacks = validatedReadyStacks(in: before),
                      let resultStacks = validatedReadyStacks(in: result),
                      entry.reason == .cashBuyIn(table: table),
                      entry.delta == -amount.rawValue,
                      amount.rawValue > 0,
                      before.id == sessionID,
                      before.table == table,
                      before.humanSeat == humanSeat,
                      result.id == sessionID,
                      result.table == table,
                      result.humanSeat == humanSeat,
                      result.dealer == before.dealer,
                      result.completedHands == before.completedHands,
                      Set(resultStacks.keys) == Set(beforeStacks.keys),
                      rebuyStacksAreValid(
                        before: beforeStacks,
                        after: resultStacks,
                        humanSeat: humanSeat,
                        amount: amount
                      )
                else {
                    throw PokerSessionError.corruptSnapshot
                }
            case .zeroStackLeave:
                guard ledgerEntriesByID[id] == nil else {
                    throw PokerSessionError.corruptSnapshot
                }
            }
        }
    }

    private func validatedReadyStacks(in view: CashSessionView) -> [SeatID: Chips]? {
        guard view.phase == .readyForHand,
              view.currentActor == nil,
              view.completedHands >= 0,
              view.seats.count == 9
        else {
            return nil
        }

        var stacks: [SeatID: Chips] = [:]
        for seat in view.seats {
            guard stacks.updateValue(seat.stack, forKey: seat.id) == nil,
                  !seat.hasFolded,
                  seat.isAllIn == (seat.stack.rawValue == 0)
            else {
                return nil
            }
        }
        guard stacks[view.humanSeat] != nil, stacks[view.dealer] != nil else {
            return nil
        }
        return stacks
    }

    private func rebuyStacksAreValid(
        before: [SeatID: Chips],
        after: [SeatID: Chips],
        humanSeat: SeatID,
        amount: Chips
    ) -> Bool {
        guard let humanBefore = before[humanSeat],
              let humanAfter = after[humanSeat]
        else {
            return false
        }
        let (expectedHumanStack, overflow) = humanBefore.rawValue
            .addingReportingOverflow(amount.rawValue)
        guard !overflow, humanAfter.rawValue == expectedHumanStack else {
            return false
        }
        for (seat, stack) in before where seat != humanSeat {
            guard after[seat] == stack else { return false }
        }
        return true
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
