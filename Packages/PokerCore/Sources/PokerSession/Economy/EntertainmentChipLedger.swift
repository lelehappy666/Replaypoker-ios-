import Foundation
import PokerCore

public enum LedgerReason: Codable, Equatable, Sendable {
    case cashBuyIn(table: TableID)
    case cashOut(table: TableID)
    case dailyGift(day: LocalDay)
    case bankruptcyRelief(day: LocalDay)
}

public struct LedgerEntry: Codable, Equatable, Sendable {
    public let businessID: BusinessID
    public let timestamp: Date
    public let reason: LedgerReason
    public let balanceBefore: Chips
    public let delta: Int
    public let balanceAfter: Chips
}

public struct EntertainmentChipLedger: Codable, Equatable, Sendable {
    public private(set) var balance: Chips
    public private(set) var entries: [LedgerEntry]
    private var entriesByBusinessID: [BusinessID: LedgerEntry]

    public init(balance: Chips = SessionEconomy.initialBalance) {
        self.balance = balance
        entries = []
        entriesByBusinessID = [:]
    }

    public mutating func buyIn(
        amount: Chips,
        table: TableID,
        id: BusinessID,
        at timestamp: Date
    ) throws -> LedgerEntry {
        guard amount.rawValue > 0 else { throw PokerSessionError.invalidBuyIn }
        return try apply(
            id: id,
            reason: .cashBuyIn(table: table),
            delta: -amount.rawValue,
            at: timestamp
        )
    }

    public mutating func cashOut(
        amount: Chips,
        table: TableID,
        id: BusinessID,
        at timestamp: Date
    ) throws -> LedgerEntry {
        guard amount.rawValue > 0 else { throw PokerSessionError.invalidBuyIn }
        return try apply(
            id: id,
            reason: .cashOut(table: table),
            delta: amount.rawValue,
            at: timestamp
        )
    }

    public mutating func claimDailyGift(
        id: BusinessID,
        day: LocalDay,
        at timestamp: Date
    ) throws -> LedgerEntry {
        let reason = LedgerReason.dailyGift(day: day)
        let delta = SessionEconomy.dailyGift.rawValue

        if entriesByBusinessID[id] != nil {
            return try apply(id: id, reason: reason, delta: delta, at: timestamp)
        }

        guard !entries.contains(where: {
            if case .dailyGift(day) = $0.reason { return true }
            return false
        }) else {
            throw PokerSessionError.dailyGiftAlreadyClaimed
        }

        return try apply(id: id, reason: reason, delta: delta, at: timestamp)
    }

    public mutating func claimRelief(
        id: BusinessID,
        day: LocalDay,
        at timestamp: Date,
        hasUnsettledBuyIn: Bool
    ) throws -> LedgerEntry {
        let reason = LedgerReason.bankruptcyRelief(day: day)

        if let existing = entriesByBusinessID[id] {
            return try apply(
                id: id,
                reason: reason,
                delta: existing.delta,
                at: timestamp
            )
        }

        guard !hasUnsettledBuyIn,
              balance < SessionEconomy.reliefThreshold,
              !entries.contains(where: {
                  if case .bankruptcyRelief(day) = $0.reason { return true }
                  return false
              })
        else {
            throw PokerSessionError.reliefNotAvailable
        }

        let (delta, overflow) = SessionEconomy.reliefTarget.rawValue
            .subtractingReportingOverflow(balance.rawValue)
        guard !overflow, delta > 0 else {
            throw PokerSessionError.chipArithmeticOverflow
        }
        return try apply(id: id, reason: reason, delta: delta, at: timestamp)
    }

    private mutating func apply(
        id: BusinessID,
        reason: LedgerReason,
        delta: Int,
        at timestamp: Date
    ) throws -> LedgerEntry {
        if let existing = entriesByBusinessID[id] {
            guard existing.reason == reason, existing.delta == delta else {
                throw PokerSessionError.businessIDConflict
            }
            return existing
        }

        let (rawBalanceAfter, overflow) = balance.rawValue.addingReportingOverflow(delta)
        guard !overflow else { throw PokerSessionError.chipArithmeticOverflow }
        guard rawBalanceAfter >= 0 else { throw PokerSessionError.insufficientBalance }

        let balanceAfter = try Chips(rawBalanceAfter)
        let entry = LedgerEntry(
            businessID: id,
            timestamp: timestamp,
            reason: reason,
            balanceBefore: balance,
            delta: delta,
            balanceAfter: balanceAfter
        )
        balance = balanceAfter
        entries.append(entry)
        entriesByBusinessID[id] = entry
        return entry
    }

    private enum CodingKeys: String, CodingKey {
        case balance
        case entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedBalance = try container.decode(Chips.self, forKey: .balance)
        let decodedEntries = try container.decode([LedgerEntry].self, forKey: .entries)

        var rebuiltIndex: [BusinessID: LedgerEntry] = [:]
        var previousBalanceAfter: Chips?
        var giftDays: Set<LocalDay> = []
        var reliefDays: Set<LocalDay> = []

        for entry in decodedEntries {
            guard rebuiltIndex.updateValue(entry, forKey: entry.businessID) == nil else {
                throw Self.corruptLedger(decoder, "Duplicate ledger business ID")
            }
            if let previousBalanceAfter {
                guard entry.balanceBefore == previousBalanceAfter else {
                    throw Self.corruptLedger(decoder, "Broken ledger balance chain")
                }
            }

            let (calculatedAfter, overflow) = entry.balanceBefore.rawValue
                .addingReportingOverflow(entry.delta)
            guard !overflow,
                  calculatedAfter >= 0,
                  calculatedAfter == entry.balanceAfter.rawValue
            else {
                throw Self.corruptLedger(decoder, "Invalid ledger arithmetic")
            }

            switch entry.reason {
            case .cashBuyIn:
                guard entry.delta < 0 else {
                    throw Self.corruptLedger(decoder, "Invalid cash buy-in delta")
                }
            case .cashOut:
                guard entry.delta > 0 else {
                    throw Self.corruptLedger(decoder, "Invalid cash-out delta")
                }
            case let .dailyGift(day):
                guard entry.delta == SessionEconomy.dailyGift.rawValue,
                      giftDays.insert(day).inserted
                else {
                    throw Self.corruptLedger(decoder, "Invalid daily gift entry")
                }
            case let .bankruptcyRelief(day):
                guard entry.delta > 0,
                      entry.balanceBefore < SessionEconomy.reliefThreshold,
                      entry.balanceAfter == SessionEconomy.reliefTarget,
                      reliefDays.insert(day).inserted
                else {
                    throw Self.corruptLedger(decoder, "Invalid relief entry")
                }
            }

            previousBalanceAfter = entry.balanceAfter
        }

        if let previousBalanceAfter {
            guard decodedBalance == previousBalanceAfter else {
                throw Self.corruptLedger(decoder, "Final ledger balance mismatch")
            }
        }

        balance = decodedBalance
        entries = decodedEntries
        entriesByBusinessID = rebuiltIndex
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(balance, forKey: .balance)
        try container.encode(entries, forKey: .entries)
    }

    private static func corruptLedger(_ decoder: Decoder, _ description: String) -> DecodingError {
        DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: description
            )
        )
    }
}
