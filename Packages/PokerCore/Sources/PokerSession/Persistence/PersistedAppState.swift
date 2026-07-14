import Foundation
import PokerCore

package struct PersistedAppState: Codable, Equatable, Sendable {
    package static let currentVersion = 2

    package var version: Int
    package var ledger: EntertainmentChipLedger
    package var activeCashSession: CashGameSession?
    package var records: [HandID: StoredHandRecord]
    package var recordOrder: [HandID]
    package var statistics: PlayerStatistics
    package var commandReceipts: [BusinessID: CommandReceipt]
    package var usedHandIDs: Set<HandID>
    package var usedSessionIDs: Set<SessionID>
    package var settlementReceipts: [BusinessID: SettlementReceipt]

    package init(
        version: Int = currentVersion,
        ledger: EntertainmentChipLedger = EntertainmentChipLedger(),
        activeCashSession: CashGameSession? = nil,
        records: [HandID: StoredHandRecord] = [:],
        recordOrder: [HandID] = [],
        statistics: PlayerStatistics = PlayerStatistics(),
        commandReceipts: [BusinessID: CommandReceipt] = [:],
        usedHandIDs: Set<HandID> = [],
        usedSessionIDs: Set<SessionID> = [],
        settlementReceipts: [BusinessID: SettlementReceipt] = [:]
    ) {
        self.version = version
        self.ledger = ledger
        self.activeCashSession = activeCashSession
        self.records = records
        self.recordOrder = recordOrder
        self.statistics = statistics
        self.commandReceipts = commandReceipts
        var inferredHandIDs = usedHandIDs.union(records.keys)
        var inferredSessionIDs = usedSessionIDs.union(records.values.map(\.sessionID))
        if let activeCashSession {
            inferredSessionIDs.insert(activeCashSession.id)
            if let activeHandID = activeCashSession.activeHandID {
                inferredHandIDs.insert(activeHandID)
            }
            if let pendingID = activeCashSession.pendingHand?.id {
                inferredHandIDs.insert(pendingID)
            }
        }
        for receipt in commandReceipts.values {
            switch receipt {
            case let .sitDown(request, _): inferredSessionIDs.insert(request.sessionID)
            case let .rebuy(sessionID, _, _, _, _, _): inferredSessionIDs.insert(sessionID)
            case let .zeroStackLeave(sessionID, _): inferredSessionIDs.insert(sessionID)
            case let .cashOut(sessionID, _, _): inferredSessionIDs.insert(sessionID)
            case .legacyCashBuyIn, .legacyCashOut: break
            case .legacyLedgerOnly: break
            }
        }
        var inferredSettlements = settlementReceipts
        for record in records.values {
            if let transactionID = record.transactionID {
                inferredSettlements[transactionID] = SettlementReceipt(
                    handID: record.id,
                    sessionID: record.sessionID
                )
            }
        }
        self.usedHandIDs = inferredHandIDs
        self.usedSessionIDs = inferredSessionIDs
        self.settlementReceipts = inferredSettlements
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case ledger
        case activeCashSession
        case records
        case recordOrder
        case statistics
        case commandReceipts
        case usedHandIDs
        case usedSessionIDs
        case settlementReceipts
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard decodedVersion == 1 || decodedVersion == Self.currentVersion else {
            throw PokerSessionError.unsupportedVersion(decodedVersion)
        }

        version = Self.currentVersion
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
        let encodedReceipts: [String: CommandReceipt]
        if decodedVersion == Self.currentVersion {
            encodedReceipts = try container.decode(
                [String: CommandReceipt].self,
                forKey: .commandReceipts
            )
        } else {
            encodedReceipts = try container.decodeIfPresent(
                [String: CommandReceipt].self,
                forKey: .commandReceipts
            ) ?? [:]
        }
        do {
            commandReceipts = try Dictionary(
                uniqueKeysWithValues: encodedReceipts.map { key, receipt in
                    (try BusinessID(key), receipt)
                }
            )
        } catch {
            throw Self.corrupt(decoder, "业务收据索引无效", underlyingError: error)
        }

        if decodedVersion == Self.currentVersion {
            usedHandIDs = try container.decode(Set<HandID>.self, forKey: .usedHandIDs)
            usedSessionIDs = try container.decode(Set<SessionID>.self, forKey: .usedSessionIDs)
        } else {
            usedHandIDs = try container.decodeIfPresent(
                Set<HandID>.self,
                forKey: .usedHandIDs
            ) ?? []
            usedSessionIDs = try container.decodeIfPresent(
                Set<SessionID>.self,
                forKey: .usedSessionIDs
            ) ?? []
        }
        let encodedSettlements: [String: SettlementReceipt]
        if decodedVersion == Self.currentVersion {
            encodedSettlements = try container.decode(
                [String: SettlementReceipt].self,
                forKey: .settlementReceipts
            )
        } else {
            encodedSettlements = try container.decodeIfPresent(
                [String: SettlementReceipt].self,
                forKey: .settlementReceipts
            ) ?? [:]
        }
        do {
            settlementReceipts = try Dictionary(uniqueKeysWithValues:
                encodedSettlements.map { key, receipt in
                    (try BusinessID(key), receipt)
                }
            )
        } catch {
            throw Self.corrupt(decoder, "结算收据索引无效", underlyingError: error)
        }

        if decodedVersion == 1 {
            usedHandIDs.formUnion(records.keys)
            if let activeCashSession {
                if let activeHandID = activeCashSession.activeHandID {
                    usedHandIDs.insert(activeHandID)
                }
                if let pendingID = activeCashSession.pendingHand?.id {
                    usedHandIDs.insert(pendingID)
                }
            }
            usedSessionIDs.formUnion(records.values.map(\.sessionID))
            if let activeCashSession {
                usedSessionIDs.insert(activeCashSession.id)
            }
            for receipt in commandReceipts.values {
                switch receipt {
                case let .sitDown(request, _): usedSessionIDs.insert(request.sessionID)
                case let .rebuy(sessionID, _, _, _, _, _): usedSessionIDs.insert(sessionID)
                case let .zeroStackLeave(sessionID, _): usedSessionIDs.insert(sessionID)
                case let .cashOut(sessionID, _, _): usedSessionIDs.insert(sessionID)
                case .legacyCashBuyIn, .legacyCashOut: break
                case .legacyLedgerOnly: break
                }
            }
            var segmentHasBuyIn = false
            var openMigratedBuyInIDs: [BusinessID] = []
            for entry in ledger.entries {
                switch entry.reason {
                case let .cashBuyIn(table):
                    let kind: LegacyCashBuyInKind = segmentHasBuyIn ? .rebuy : .sitDown
                    segmentHasBuyIn = true
                    if commandReceipts[entry.businessID] == nil {
                        commandReceipts[entry.businessID] = .legacyCashBuyIn(
                            kind: kind,
                            table: table,
                            amount: try Chips(-entry.delta),
                            belongsToOpenSession: false
                        )
                        openMigratedBuyInIDs.append(entry.businessID)
                    }
                case .cashOut:
                    if commandReceipts[entry.businessID] == nil {
                        commandReceipts[entry.businessID] = .legacyCashOut(
                            reason: entry.reason
                        )
                    }
                    segmentHasBuyIn = false
                    openMigratedBuyInIDs.removeAll()
                case .dailyGift, .bankruptcyRelief:
                    break
                }
            }
            for id in openMigratedBuyInIDs {
                guard case let .legacyCashBuyIn(kind, table, amount, _) = commandReceipts[id]
                else { continue }
                commandReceipts[id] = .legacyCashBuyIn(
                    kind: kind,
                    table: table,
                    amount: amount,
                    belongsToOpenSession: true
                )
            }
            for record in records.values {
                if let transactionID = record.transactionID {
                    settlementReceipts[transactionID] = SettlementReceipt(
                        handID: record.id,
                        sessionID: record.sessionID
                    )
                }
            }
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
        try container.encode(usedHandIDs, forKey: .usedHandIDs)
        try container.encode(usedSessionIDs, forKey: .usedSessionIDs)
        try container.encode(
            Dictionary(uniqueKeysWithValues: settlementReceipts.map {
                ($0.key.rawValue, $0.value)
            }),
            forKey: .settlementReceipts
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
        let permanentSettlementBusinessIDs = Set(settlementReceipts.keys)
        guard ledgerBusinessIDs.isDisjoint(with: settlementBusinessIDs),
              settlementBusinessIDs.isDisjoint(with: receiptBusinessIDs),
              ledgerBusinessIDs.isDisjoint(with: permanentSettlementBusinessIDs),
              receiptBusinessIDs.isDisjoint(with: permanentSettlementBusinessIDs),
              settlementBusinessIDs.count
                == records.values.compactMap(\.transactionID).count
        else {
            throw PokerSessionError.corruptSnapshot
        }

        guard Set(records.keys).isSubset(of: usedHandIDs),
              Set(records.values.map(\.sessionID)).isSubset(of: usedSessionIDs),
              activeCashSession?.phase != .left,
              activeCashSession.map({ usedSessionIDs.contains($0.id) }) ?? true,
              activeCashSession?.activeHandID.map({ usedHandIDs.contains($0) }) ?? true
        else {
            throw PokerSessionError.corruptSnapshot
        }
        var settledHands: Set<HandID> = []
        for (id, receipt) in settlementReceipts {
            guard usedHandIDs.contains(receipt.handID),
                  usedSessionIDs.contains(receipt.sessionID),
                  settledHands.insert(receipt.handID).inserted
            else {
                throw PokerSessionError.corruptSnapshot
            }
            if let record = records[receipt.handID] {
                guard record.transactionID == id,
                      record.sessionID == receipt.sessionID
                else {
                    throw PokerSessionError.corruptSnapshot
                }
            }
        }
        for record in records.values {
            guard let transactionID = record.transactionID else { continue }
            guard settlementReceipts[transactionID] == SettlementReceipt(
                handID: record.id,
                sessionID: record.sessionID
            ) else {
                throw PokerSessionError.corruptSnapshot
            }
        }

        var expectedLegacyBuyInKinds: [BusinessID: LegacyCashBuyInKind] = [:]
        var openLegacyBuyInIDs: Set<BusinessID> = []
        var segmentHasBuyIn = false
        for entry in ledger.entries {
            switch entry.reason {
            case .cashBuyIn:
                let kind: LegacyCashBuyInKind = segmentHasBuyIn ? .rebuy : .sitDown
                segmentHasBuyIn = true
                if case .legacyCashBuyIn = commandReceipts[entry.businessID] {
                    expectedLegacyBuyInKinds[entry.businessID] = kind
                    openLegacyBuyInIDs.insert(entry.businessID)
                }
            case .cashOut:
                segmentHasBuyIn = false
                openLegacyBuyInIDs.removeAll()
            case .dailyGift, .bankruptcyRelief:
                break
            }
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
                      usedSessionIDs.contains(request.sessionID),
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
                      usedSessionIDs.contains(sessionID),
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
            case let .zeroStackLeave(sessionID, _):
                guard ledgerEntriesByID[id] == nil,
                      usedSessionIDs.contains(sessionID)
                else {
                    throw PokerSessionError.corruptSnapshot
                }
            case let .cashOut(sessionID, table, amount):
                guard let entry = ledgerEntriesByID[id],
                      entry.reason == .cashOut(table: table),
                      entry.delta == amount.rawValue,
                      usedSessionIDs.contains(sessionID)
                else {
                    throw PokerSessionError.corruptSnapshot
                }
            case let .legacyCashBuyIn(kind, table, amount, belongsToOpenSession):
                guard let entry = ledgerEntriesByID[id],
                      entry.reason == .cashBuyIn(table: table),
                      entry.delta == -amount.rawValue,
                      expectedLegacyBuyInKinds[id] == kind,
                      openLegacyBuyInIDs.contains(id) == belongsToOpenSession
                else {
                    throw PokerSessionError.corruptSnapshot
                }
            case let .legacyCashOut(reason):
                guard case .cashOut = reason else {
                    throw PokerSessionError.corruptSnapshot
                }
                guard let entry = ledgerEntriesByID[id],
                      entry.reason == reason
                else {
                    throw PokerSessionError.corruptSnapshot
                }
            case let .legacyLedgerOnly(reason):
                guard let entry = ledgerEntriesByID[id], entry.reason == reason else {
                    throw PokerSessionError.corruptSnapshot
                }
            }
        }
        for entry in ledger.entries {
            switch entry.reason {
            case .cashBuyIn, .cashOut:
                guard commandReceipts[entry.businessID] != nil else {
                    throw PokerSessionError.corruptSnapshot
                }
            case .dailyGift, .bankruptcyRelief:
                break
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
