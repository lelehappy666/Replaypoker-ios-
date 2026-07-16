import Foundation
import PokerCore
import PokerSession

struct HandHistoryListItem: Identifiable, Equatable, Sendable {
    let id: HandID
    let tableID: TableID
    let tableName: String
    let endedAt: Date
    let localDay: LocalDay
    let handNumber: Int
    let blindsText: String
    let completedAtText: String
    let allocatedPotTotal: Chips
    let allocatedPotTotalText: String
    let communityCards: [Card]
    let humanChipDelta: Int?
    let humanChipDeltaText: String
}

struct HandHistoryTableOption: Identifiable, Equatable, Sendable {
    let id: TableID
    let name: String
}

struct HandHistoryDetail: Identifiable, Equatable, Sendable {
    let id: HandID
    let tableName: String
    let startedAt: Date
    let endedAt: Date
    let localDay: LocalDay
    let handNumber: Int
    let blindsText: String
    let completedAtText: String
    let communityCards: [Card]
    let seats: [HandHistorySeatResult]
    let pots: [HandHistoryPotResult]
    let uncalledReturns: [HandHistoryNamedAmount]
}

struct HandHistorySeatResult: Identifiable, Equatable, Sendable {
    let id: SeatID
    let displayName: String
    let cards: [Card]
    let status: HandHistorySeatStatus
    let startingStack: Chips
    let finalStack: Chips
    let chipDelta: Int
    let chipDeltaText: String
    let stackSummaryText: String
}

struct HandHistoryPotResult: Identifiable, Equatable, Sendable {
    let id: Int
    let amount: Chips
    let amounts: [SeatID: Chips]
    let winnerAmounts: [HandHistoryNamedAmount]
}

struct HandHistoryNamedAmount: Identifiable, Equatable, Sendable {
    let seatID: SeatID
    let displayName: String
    let amount: Chips

    var id: SeatID { seatID }
}

enum HandHistorySeatStatus: Equatable, Sendable {
    case winner
    case folded
    case showdown
    case notDealt
}

enum HandHistoryPresentation {
    static func listItem(
        from record: StoredHandRecord,
        timeZone: TimeZone = .autoupdatingCurrent
    ) throws -> HandHistoryListItem {
        let humanSeat = record.archiveMetadata?.humanSeat
        let humanChipDelta = humanSeat.flatMap { record.record.chipDeltas[$0] }
        let allocatedPotTotalRaw = try checkedSum(
            record.record.awards.values.map(\.rawValue)
        )
        guard let allocatedPotTotal = Chips(rawValue: allocatedPotTotalRaw) else {
            throw PokerRuleError.invalidState("invalid allocated pot total")
        }
        return HandHistoryListItem(
            id: record.id,
            tableID: record.table,
            tableName: tableName(for: record),
            endedAt: record.endedAt,
            localDay: record.localDay,
            handNumber: record.handNumber,
            blindsText: blindsText(for: record),
            completedAtText: completedAtText(
                record.endedAt,
                timeZone: timeZone
            ),
            allocatedPotTotal: allocatedPotTotal,
            allocatedPotTotalText: "已分配底池 \(allocatedPotTotalRaw.formatted())",
            communityCards: record.record.communityCards,
            humanChipDelta: humanChipDelta,
            humanChipDeltaText: humanChipDelta.map(chipDeltaText)
                ?? "未知（旧记录不可用）"
        )
    }

    static func detail(
        from record: StoredHandRecord,
        timeZone: TimeZone = .autoupdatingCurrent
    ) throws -> HandHistoryDetail {
        let foldedSeats = Set(
            record.record.actions.compactMap { action in
                action.action == .fold ? action.seat : nil
            }
        )
        let zero = Chips(rawValue: 0)!
        let seats = try record.record.startingStacks.keys.sorted().map { seat in
            guard let startingStack = record.record.startingStacks[seat],
                  let finalStack = record.record.finalStacks[seat],
                  let chipDelta = record.record.chipDeltas[seat]
            else {
                throw PokerRuleError.invalidState("missing history seat result")
            }

            let status: HandHistorySeatStatus
            if record.record.awards[seat, default: zero].rawValue > 0 {
                status = .winner
            } else if foldedSeats.contains(seat) {
                status = .folded
            } else if record.record.holeCardsBySeat[seat] != nil {
                status = .showdown
            } else {
                status = .notDealt
            }

            let deltaText = chipDeltaText(chipDelta)
            return HandHistorySeatResult(
                id: seat,
                displayName: displayName(for: seat, in: record),
                cards: record.record.holeCardsBySeat[seat] ?? [],
                status: status,
                startingStack: startingStack,
                finalStack: finalStack,
                chipDelta: chipDelta,
                chipDeltaText: deltaText,
                stackSummaryText: "起始 \(startingStack.rawValue.formatted()) · 最终 \(finalStack.rawValue.formatted()) · 净变化 \(deltaText)"
            )
        }

        let pots = try record.record.pots.enumerated().map { index, pot in
            let amounts: [SeatID: Chips]
            if pot.eligible.count == 1, record.record.handRanksBySeat.isEmpty {
                guard let winner = pot.eligible.first else {
                    throw PokerRuleError.invalidState("pot has no eligible seats")
                }
                amounts = [winner: pot.amount]
            } else {
                amounts = try PotBuilder.awards(
                    for: [pot],
                    ranks: record.record.handRanksBySeat,
                    dealer: record.record.config.dealer
                )
            }
            let winnerAmounts = amounts.keys.sorted().compactMap { seat in
                amounts[seat].map {
                    HandHistoryNamedAmount(
                        seatID: seat,
                        displayName: displayName(for: seat, in: record),
                        amount: $0
                    )
                }
            }
            return HandHistoryPotResult(
                id: index,
                amount: pot.amount,
                amounts: amounts,
                winnerAmounts: winnerAmounts
            )
        }

        let rebuiltTotal = try checkedSum(
            pots.flatMap(\.amounts).map { $0.value.rawValue }
        )
        let recordedTotal = try checkedSum(record.record.awards.values.map(\.rawValue))
        guard rebuiltTotal == recordedTotal else {
            throw PokerRuleError.invalidState("history award total mismatch")
        }

        return HandHistoryDetail(
            id: record.id,
            tableName: tableName(for: record),
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            localDay: record.localDay,
            handNumber: record.handNumber,
            blindsText: blindsText(for: record),
            completedAtText: completedAtText(
                record.endedAt,
                timeZone: timeZone
            ),
            communityCards: record.record.communityCards,
            seats: seats,
            pots: pots,
            uncalledReturns: record.record.uncalledReturns.keys.sorted().compactMap {
                seat in
                record.record.uncalledReturns[seat].map {
                    HandHistoryNamedAmount(
                        seatID: seat,
                        displayName: displayName(for: seat, in: record),
                        amount: $0
                    )
                }
            }
        )
    }

    static func storeFilter(
        filters: HandHistoryFilters,
        today: LocalDay,
        calendar: Calendar
    ) throws -> HandRecordFilter {
        switch filters.dateSelection {
        case .all:
            return HandRecordFilter(table: filters.table)
        case .today:
            return HandRecordFilter(table: filters.table, localDay: today)
        case let .custom(day):
            return HandRecordFilter(table: filters.table, localDay: day)
        case .lastSevenDays:
            let first = try offset(day: today, by: -6, calendar: calendar)
            return HandRecordFilter(
                table: filters.table,
                dateRange: try HandRecordDateRange(first: first, last: today)
            )
        }
    }

    private static func tableName(for record: StoredHandRecord) -> String {
        record.archiveMetadata?.tableDisplayName ?? "牌桌 \(record.table.rawValue)"
    }

    private static func displayName(for seat: SeatID, in record: StoredHandRecord) -> String {
        record.archiveMetadata?.seatDisplayNames[seat] ?? "座位 \(seat.rawValue + 1)"
    }

    private static func blindsText(for record: StoredHandRecord) -> String {
        "小盲 \(record.record.config.smallBlind.rawValue.formatted()) · 大盲 \(record.record.config.bigBlind.rawValue.formatted())"
    }

    private static func completedAtText(
        _ date: Date,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func chipDeltaText(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta.formatted())" }
        if delta < 0 {
            let magnitude = delta == Int.min ? "\(UInt(Int.max) + 1)" : (-delta).formatted()
            return "−\(magnitude)"
        }
        return "0"
    }

    private static func offset(
        day: LocalDay,
        by value: Int,
        calendar: Calendar
    ) throws -> LocalDay {
        let values = day.rawValue.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3,
              let date = calendar.date(
                  from: DateComponents(year: values[0], month: values[1], day: values[2])
              ),
              let offsetDate = calendar.date(byAdding: .day, value: value, to: date)
        else {
            throw PokerSessionError.invalidIdentifier
        }
        let components = calendar.dateComponents([.year, .month, .day], from: offsetDate)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            throw PokerSessionError.invalidIdentifier
        }
        return try LocalDay(String(format: "%04d-%02d-%02d", year, month, day))
    }

    private static func checkedSum(_ values: [Int]) throws -> Int {
        try values.reduce(0) { total, value in
            let (result, overflow) = total.addingReportingOverflow(value)
            guard !overflow else {
                throw PokerRuleError.invalidState("chip arithmetic overflow")
            }
            return result
        }
    }
}
