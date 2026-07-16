import Foundation
import PokerCore

public struct CashTableRequest: Codable, Equatable, Sendable {
    public let sessionID: SessionID
    public let table: TableID
    public let config: HandConfig
    public let humanSeat: SeatID
    public let stacks: [SeatID: Chips]

    public init(
        sessionID: SessionID,
        table: TableID,
        config: HandConfig,
        humanSeat: SeatID,
        stacks: [SeatID: Chips]
    ) {
        self.sessionID = sessionID
        self.table = table
        self.config = config
        self.humanSeat = humanSeat
        self.stacks = stacks
    }
}

public final class LocalPokerStore {
    private let repository: any SessionRepository
    private let clock: any SessionClock
    private var committed: PersistedAppState

    package init(repository: any SessionRepository, clock: any SessionClock) throws {
        self.repository = repository
        self.clock = clock
        committed = try repository.load()
    }

    public static func open(
        directory: URL,
        clock: any SessionClock
    ) throws -> LocalPokerStore {
        try LocalPokerStore(
            repository: FileSessionRepository(directory: directory),
            clock: clock
        )
    }

    public var accountBalance: Chips { committed.ledger.balance }

    public var cashSession: CashSessionView? {
        committed.activeCashSession?.view
    }

    public var spectatorObservation: SpectatorObservation? {
        committed.activeCashSession?.spectatorObservation()
    }

    package func playerObservation(for seat: SeatID) throws -> PlayerObservation? {
        try committed.activeCashSession?.playerObservation(for: seat)
    }

    package func refillBotSeat(_ seat: SeatID, to target: Chips) throws {
        try transact { state in
            guard var session = state.activeCashSession,
                  seat != session.humanSeat,
                  let current = session.stacks[seat],
                  current.rawValue == 0,
                  target.rawValue > 0 else {
                throw PokerSessionError.invalidTable
            }
            try session.addChips(
                try Chips(target.rawValue - current.rawValue),
                to: seat
            )
            state.activeCashSession = session
        }
    }

    package var pendingShowdownObservation: CashShowdownObservation? {
        committed.activeCashSession?.pendingHand.map {
            CashShowdownObservation(record: $0.record)
        }
    }

    package var activeCashConfig: HandConfig? {
        committed.activeCashSession?.config
    }

    public func humanObservation() throws -> PlayerObservation? {
        guard let session = committed.activeCashSession else { return nil }
        return try session.playerObservation(for: session.humanSeat)
    }

    public var statistics: PlayerStatisticsView {
        PlayerStatisticsView(committed.statistics)
    }

    public func handRecords(filter: HandRecordFilter = .init()) -> [StoredHandRecord] {
        committed.records.values
            .filter { record in
                (filter.table == nil || record.table == filter.table)
                    && (filter.localDay == nil || record.localDay == filter.localDay)
                    && (filter.dateRange == nil
                        || filter.dateRange!.contains(record.localDay))
            }
            .sorted {
                if $0.endedAt != $1.endedAt { return $0.endedAt > $1.endedAt }
                if $0.handNumber != $1.handNumber {
                    return $0.handNumber > $1.handNumber
                }
                return $0.id.rawValue > $1.id.rawValue
            }
    }

    public func deleteHand(id: HandID) throws {
        try transact { state in
            guard state.records.removeValue(forKey: id) != nil else {
                throw PokerSessionError.recordNotFound
            }
            state.recordOrder.removeAll { $0 == id }
        }
    }

    public func deleteAllHands(confirmation: DeleteAllConfirmation) throws {
        try transact { state in
            state.records.removeAll()
            state.recordOrder.removeAll()
        }
    }

    public func sitDown(
        request: CashTableRequest,
        businessID: BusinessID
    ) throws -> CashSessionView {
        if let receipt = committed.commandReceipts[businessID] {
            switch receipt {
            case let .sitDown(storedRequest, result):
                guard storedRequest == request else {
                    throw PokerSessionError.businessIDConflict
                }
                return result
            case let .legacyCashBuyIn(kind, table, amount, belongsToOpenSession):
                guard kind == .sitDown, belongsToOpenSession else {
                    throw PokerSessionError.businessIDConflict
                }
                return try legacySitDownRetry(
                    request: request,
                    businessID: businessID,
                    table: table,
                    amount: amount
                )
            case .rebuy, .zeroStackLeave, .cashOut, .legacyCashOut,
                 .legacyLedgerOnly:
                throw PokerSessionError.businessIDConflict
            }
        }
        try requireAvailableForLedgerCommand(businessID)
        if let existing = ledgerEntry(for: businessID) {
            try validateBuyInEntry(
                existing,
                amount: try humanStack(in: request),
                table: request.table
            )
            guard let session = committed.activeCashSession,
                  session.id == request.sessionID,
                  session.table == request.table,
                  session.humanSeat == request.humanSeat,
                  session.config == request.config
            else {
                throw PokerSessionError.businessIDConflict
            }
            if session.phase == .readyForHand, session.completedHands == 0,
               session.stacks != request.stacks {
                throw PokerSessionError.businessIDConflict
            }
            return session.view
        }

        return try transact { state in
            guard state.activeCashSession == nil else {
                throw PokerSessionError.invalidLifecycle
            }
            guard !state.usedSessionIDs.contains(request.sessionID) else {
                throw PokerSessionError.businessIDConflict
            }
            let session = try CashGameSession.make(
                id: request.sessionID,
                table: request.table,
                config: request.config,
                humanSeat: request.humanSeat,
                stacks: request.stacks
            )
            _ = try state.ledger.buyIn(
                amount: try humanStack(in: request),
                table: request.table,
                id: businessID,
                at: clock.now
            )
            state.activeCashSession = session
            state.usedSessionIDs.insert(request.sessionID)
            state.commandReceipts[businessID] = .sitDown(
                request: request,
                result: session.view
            )
            return session.view
        }
    }

    public func startHand(id: HandID) throws -> GameTransition {
        try startHand(id: id, seed: UInt64.random(in: UInt64.min...UInt64.max))
    }

    package func startHand(id: HandID, seed: UInt64) throws -> GameTransition {
        try transact { state in
            guard !state.usedHandIDs.contains(id) else {
                throw PokerSessionError.businessIDConflict
            }
            guard var session = state.activeCashSession else {
                throw PokerSessionError.invalidLifecycle
            }
            let transition = try session.startHand(id: id, seed: seed, startedAt: clock.now)
            state.activeCashSession = session
            state.usedHandIDs.insert(id)
            return transition
        }
    }

    public func apply(_ action: PlayerAction, by seat: SeatID) throws -> GameTransition {
        try transact { state in
            guard var session = state.activeCashSession else {
                throw PokerSessionError.invalidLifecycle
            }
            let transition = try session.apply(action, by: seat)
            state.activeCashSession = session
            return transition
        }
    }

    public func advanceIfRoundComplete() throws -> GameTransition {
        try transact { state in
            guard var session = state.activeCashSession else {
                throw PokerSessionError.invalidLifecycle
            }
            let transition = try session.advanceIfRoundComplete()
            state.activeCashSession = session
            return transition
        }
    }

    public func commitPendingHand(
        transactionID: BusinessID,
        archiveMetadata: HandArchiveMetadata
    ) throws -> StoredHandRecord {
        if let receipt = committed.settlementReceipts[transactionID] {
            guard let record = committed.records[receipt.handID] else {
                throw PokerSessionError.recordNotFound
            }
            guard record.sessionID == receipt.sessionID,
                  record.transactionID == transactionID,
                  record.archiveMetadata == archiveMetadata,
                  committed.activeCashSession?.pendingHand == nil
            else {
                throw PokerSessionError.businessIDConflict
            }
            return record
        }
        guard ledgerEntry(for: transactionID) == nil,
              committed.commandReceipts[transactionID] == nil
        else {
            throw PokerSessionError.businessIDConflict
        }

        return try transact { state in
            guard var session = state.activeCashSession,
                  let pending = session.pendingHand
            else {
                throw PokerSessionError.handNotComplete
            }
            guard Set(archiveMetadata.seatDisplayNames.keys)
                    == Set(session.stacks.keys),
                  archiveMetadata.humanSeat == session.humanSeat
            else {
                throw PokerSessionError.invalidTable
            }
            if let existing = state.records[pending.id] {
                guard existing.transactionID == transactionID,
                      existing.archiveMetadata == archiveMetadata
                else {
                    throw PokerSessionError.businessIDConflict
                }
                return existing
            }

            let (handNumber, handNumberOverflow) = session.completedHands
                .addingReportingOverflow(1)
            guard !handNumberOverflow else {
                throw PokerSessionError.chipArithmeticOverflow
            }
            let stored = StoredHandRecord(
                id: pending.id,
                transactionID: transactionID,
                sessionID: session.id,
                table: session.table,
                startedAt: pending.startedAt,
                endedAt: clock.now,
                localDay: clock.currentDay,
                handNumber: handNumber,
                record: pending.record,
                archiveMetadata: archiveMetadata
            )
            try updateStatistics(
                &state.statistics,
                record: pending.record,
                humanSeat: session.humanSeat
            )
            try session.markHandCommitted(pending.id)
            state.records[pending.id] = stored
            state.recordOrder.append(pending.id)
            state.settlementReceipts[transactionID] = SettlementReceipt(
                handID: pending.id,
                sessionID: session.id
            )
            state.activeCashSession = session
            return stored
        }
    }

    public func leave(businessID: BusinessID) throws {
        if let receipt = committed.commandReceipts[businessID] {
            switch receipt {
            case .zeroStackLeave, .cashOut:
                guard committed.activeCashSession == nil else {
                    throw PokerSessionError.businessIDConflict
                }
                return
            case .sitDown, .rebuy:
                throw PokerSessionError.businessIDConflict
            case let .legacyCashOut(reason):
                guard let existing = ledgerEntry(for: businessID),
                      case .cashOut = reason,
                      existing.reason == reason,
                      case .cashOut = existing.reason,
                      committed.activeCashSession == nil
                else {
                    throw PokerSessionError.businessIDConflict
                }
                return
            case .legacyCashBuyIn, .legacyLedgerOnly:
                throw PokerSessionError.businessIDConflict
            }
        }
        try requireAvailableForLedgerCommand(businessID)
        if let existing = ledgerEntry(for: businessID) {
            guard case .cashOut = existing.reason else {
                throw PokerSessionError.businessIDConflict
            }
            guard committed.activeCashSession == nil else {
                throw PokerSessionError.businessIDConflict
            }
            return
        }

        try transact { state in
            guard var session = state.activeCashSession else {
                throw PokerSessionError.invalidLifecycle
            }
            let humanStack = try session.leave()
            if humanStack.rawValue == 0 {
                state.commandReceipts[businessID] = .zeroStackLeave(
                    sessionID: session.id,
                    table: session.table
                )
            } else {
                _ = try state.ledger.cashOut(
                    amount: humanStack,
                    table: session.table,
                    id: businessID,
                    at: clock.now
                )
                state.commandReceipts[businessID] = .cashOut(
                    sessionID: session.id,
                    table: session.table,
                    amount: humanStack
                )
            }
            state.activeCashSession = nil
        }
    }

    public func rebuyHuman(
        amount: Chips,
        businessID: BusinessID
    ) throws -> CashSessionView {
        if let receipt = committed.commandReceipts[businessID] {
            if case let .legacyCashBuyIn(
                kind,
                table,
                storedAmount,
                belongsToOpenSession
            ) = receipt {
                guard let existing = ledgerEntry(for: businessID),
                      let session = committed.activeCashSession,
                      kind == .rebuy,
                      belongsToOpenSession,
                      storedAmount == amount,
                      session.table == table,
                      existing.reason == .cashBuyIn(table: table)
                else {
                    throw PokerSessionError.businessIDConflict
                }
                try validateBuyInEntry(existing, amount: amount, table: session.table)
                return session.view
            }
            guard case let .rebuy(
                sessionID,
                table,
                humanSeat,
                storedAmount,
                _,
                result
            ) = receipt,
                storedAmount == amount,
                committed.activeCashSession == nil
                    || (
                        committed.activeCashSession?.id == sessionID
                            && committed.activeCashSession?.table == table
                            && committed.activeCashSession?.humanSeat == humanSeat
                    )
            else {
                throw PokerSessionError.businessIDConflict
            }
            return result
        }
        try requireAvailableForLedgerCommand(businessID)
        if let existing = ledgerEntry(for: businessID) {
            guard let session = committed.activeCashSession else {
                throw PokerSessionError.businessIDConflict
            }
            try validateBuyInEntry(existing, amount: amount, table: session.table)
            return session.view
        }

        return try transact { state in
            guard var session = state.activeCashSession else {
                throw PokerSessionError.invalidLifecycle
            }
            let before = session.view
            _ = try state.ledger.buyIn(
                amount: amount,
                table: session.table,
                id: businessID,
                at: clock.now
            )
            try session.addChips(amount, to: session.humanSeat)
            state.activeCashSession = session
            state.commandReceipts[businessID] = .rebuy(
                sessionID: session.id,
                table: session.table,
                humanSeat: session.humanSeat,
                amount: amount,
                before: before,
                result: session.view
            )
            return session.view
        }
    }

    public func claimDailyGift(businessID: BusinessID) throws -> LedgerEntry {
        try requireAvailableForLedgerCommand(businessID)
        if let existing = ledgerEntry(for: businessID) {
            guard existing.reason == .dailyGift(day: clock.currentDay),
                  existing.delta == SessionEconomy.dailyGift.rawValue
            else {
                throw PokerSessionError.businessIDConflict
            }
            return existing
        }
        return try transact { state in
            try state.ledger.claimDailyGift(
                id: businessID,
                day: clock.currentDay,
                at: clock.now
            )
        }
    }

    public func claimRelief(businessID: BusinessID) throws -> LedgerEntry {
        try requireAvailableForLedgerCommand(businessID)
        if let existing = ledgerEntry(for: businessID) {
            guard existing.reason == .bankruptcyRelief(day: clock.currentDay) else {
                throw PokerSessionError.businessIDConflict
            }
            return existing
        }
        return try transact { state in
            try state.ledger.claimRelief(
                id: businessID,
                day: clock.currentDay,
                at: clock.now,
                hasUnsettledBuyIn: false
            )
        }
    }

    private func transact<Result>(
        _ operation: (inout PersistedAppState) throws -> Result
    ) throws -> Result {
        var candidate = committed
        let result = try operation(&candidate)
        do {
            try repository.save(candidate)
        } catch {
            throw PokerSessionError.persistenceFailed
        }
        committed = candidate
        return result
    }

    private func ledgerEntry(for id: BusinessID) -> LedgerEntry? {
        committed.ledger.entries.first { $0.businessID == id }
    }

    private func requireAvailableForLedgerCommand(_ id: BusinessID) throws {
        guard committed.commandReceipts[id] == nil,
              committed.settlementReceipts[id] == nil
        else {
            throw PokerSessionError.businessIDConflict
        }
    }

    private func humanStack(in request: CashTableRequest) throws -> Chips {
        guard let stack = request.stacks[request.humanSeat] else {
            throw PokerSessionError.invalidTable
        }
        return stack
    }

    private func validateBuyInEntry(
        _ entry: LedgerEntry,
        amount: Chips,
        table: TableID
    ) throws {
        guard entry.reason == .cashBuyIn(table: table),
              entry.delta == -amount.rawValue
        else {
            throw PokerSessionError.businessIDConflict
        }
    }

    private func legacySitDownRetry(
        request: CashTableRequest,
        businessID: BusinessID,
        table: TableID,
        amount: Chips
    ) throws -> CashSessionView {
        guard let existing = ledgerEntry(for: businessID),
              request.table == table,
              try humanStack(in: request) == amount,
              existing.reason == .cashBuyIn(table: table)
        else {
            throw PokerSessionError.businessIDConflict
        }
        try validateBuyInEntry(
            existing,
            amount: try humanStack(in: request),
            table: request.table
        )
        guard let session = committed.activeCashSession,
              session.id == request.sessionID,
              session.table == request.table,
              session.humanSeat == request.humanSeat,
              session.config == request.config
        else {
            throw PokerSessionError.businessIDConflict
        }
        if session.phase == .readyForHand, session.completedHands == 0,
           session.stacks != request.stacks {
            throw PokerSessionError.businessIDConflict
        }
        return session.view
    }

    private func updateStatistics(
        _ statistics: inout PlayerStatistics,
        record: CompletedHandRecord,
        humanSeat: SeatID
    ) throws {
        guard let commitment = record.settledCommitments[humanSeat]?.rawValue,
              let delta = record.chipDeltas[humanSeat]
        else {
            throw PokerSessionError.corruptSnapshot
        }
        statistics.completedHands = try checkedAdd(statistics.completedHands, 1)
        if record.awards[humanSeat] != nil {
            statistics.wonHands = try checkedAdd(statistics.wonHands, 1)
        }
        statistics.totalCommitted = try checkedAdd(statistics.totalCommitted, commitment)
        statistics.netChange = try checkedAdd(statistics.netChange, delta)
        if delta > statistics.largestWin {
            statistics.largestWin = delta
        }
    }

    private func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw PokerSessionError.chipArithmeticOverflow }
        return result
    }
}
