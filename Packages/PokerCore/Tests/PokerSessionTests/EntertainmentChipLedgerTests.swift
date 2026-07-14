import Foundation
import PokerCore
import Testing
@testable import PokerSession

@Test func buyInAndCashOutCreateAuditableEntries() throws {
    var ledger = EntertainmentChipLedger()
    let table = try TableID("jade")
    let bought = try ledger.buyIn(
        amount: try Chips(5_000),
        table: table,
        id: try BusinessID("buy-1"),
        at: Date(timeIntervalSince1970: 1)
    )
    #expect(bought.balanceBefore == (try Chips(128_500)))
    #expect(bought.delta == -5_000)
    #expect(ledger.balance == (try Chips(123_500)))

    let returned = try ledger.cashOut(
        amount: try Chips(6_250),
        table: table,
        id: try BusinessID("out-1"),
        at: Date(timeIntervalSince1970: 2)
    )
    #expect(returned.delta == 6_250)
    #expect(ledger.balance == (try Chips(129_750)))
}

@Test func repeatingSameBusinessCommandIsIdempotentAndKeepsOriginalTimestamp() throws {
    var ledger = EntertainmentChipLedger()
    let id = try BusinessID("gift-2026-07-14")
    let day = try LocalDay("2026-07-14")
    let first = try ledger.claimDailyGift(id: id, day: day, at: .distantPast)
    let second = try ledger.claimDailyGift(id: id, day: day, at: .distantFuture)
    #expect(first == second)
    #expect(second.timestamp == .distantPast)
    #expect(ledger.balance == (try Chips(138_500)))
    #expect(ledger.entries.count == 1)
}

@Test func conflictingReuseOfBusinessIDIsRejected() throws {
    var ledger = EntertainmentChipLedger()
    let id = try BusinessID("same-id")
    let table = try TableID("jade")
    _ = try ledger.buyIn(
        amount: try Chips(4_000), table: table, id: id, at: .distantPast
    )
    #expect(throws: PokerSessionError.businessIDConflict) {
        try ledger.cashOut(
            amount: try Chips(4_000), table: table, id: id, at: .distantFuture
        )
    }
}

@Test func reliefRequiresLowBalanceNoUnsettledBuyInAndOneClaimPerDay() throws {
    var ledger = EntertainmentChipLedger(balance: try Chips(1_500))
    let day = try LocalDay("2026-07-14")
    #expect(throws: PokerSessionError.reliefNotAvailable) {
        try ledger.claimRelief(
            id: try BusinessID("relief-blocked"),
            day: day,
            at: .distantPast,
            hasUnsettledBuyIn: true
        )
    }
    let entry = try ledger.claimRelief(
        id: try BusinessID("relief-ok"),
        day: day,
        at: .distantPast,
        hasUnsettledBuyIn: false
    )
    #expect(entry.delta == 18_500)
    #expect(ledger.balance == (try Chips(20_000)))
    #expect(throws: PokerSessionError.reliefNotAvailable) {
        try ledger.claimRelief(
            id: try BusinessID("relief-again"),
            day: day,
            at: .distantFuture,
            hasUnsettledBuyIn: false
        )
    }
}

@Test func buyInRejectsInsufficientBalanceWithoutMutation() throws {
    var ledger = EntertainmentChipLedger(balance: try Chips(3_999))
    let original = ledger
    #expect(throws: PokerSessionError.insufficientBalance) {
        try ledger.buyIn(
            amount: try Chips(4_000),
            table: try TableID("jade"),
            id: try BusinessID("too-much"),
            at: .distantPast
        )
    }
    #expect(ledger == original)
}

@Test func dailyGiftAllowsOnlyOneClaimPerDayButAllowsAnotherDay() throws {
    var ledger = EntertainmentChipLedger()
    let firstDay = try LocalDay("2026-07-14")
    _ = try ledger.claimDailyGift(
        id: try BusinessID("gift-1"), day: firstDay, at: .distantPast
    )
    #expect(throws: PokerSessionError.dailyGiftAlreadyClaimed) {
        try ledger.claimDailyGift(
            id: try BusinessID("gift-2"), day: firstDay, at: .distantFuture
        )
    }

    _ = try ledger.claimDailyGift(
        id: try BusinessID("gift-3"),
        day: try LocalDay("2026-07-15"),
        at: .distantFuture
    )
    #expect(ledger.balance == (try Chips(148_500)))
    #expect(ledger.entries.count == 2)
}

@Test func cashOutAndDailyGiftRejectAdditionOverflowWithoutMutation() throws {
    let table = try TableID("jade")
    var cashOutLedger = EntertainmentChipLedger(balance: try Chips(Int.max))
    #expect(throws: PokerSessionError.chipArithmeticOverflow) {
        try cashOutLedger.cashOut(
            amount: try Chips(1),
            table: table,
            id: try BusinessID("overflow-out"),
            at: .distantPast
        )
    }
    #expect(cashOutLedger.balance == (try Chips(Int.max)))
    #expect(cashOutLedger.entries.isEmpty)

    var giftLedger = EntertainmentChipLedger(
        balance: try Chips(Int.max - SessionEconomy.dailyGift.rawValue + 1)
    )
    #expect(throws: PokerSessionError.chipArithmeticOverflow) {
        try giftLedger.claimDailyGift(
            id: try BusinessID("overflow-gift"),
            day: try LocalDay("2026-07-14"),
            at: .distantPast
        )
    }
    #expect(giftLedger.entries.isEmpty)
}

@Test func zeroValueBuyInAndCashOutAreRejected() throws {
    var ledger = EntertainmentChipLedger()
    let table = try TableID("jade")
    #expect(throws: PokerSessionError.invalidBuyIn) {
        try ledger.buyIn(
            amount: try Chips(0),
            table: table,
            id: try BusinessID("zero-buy"),
            at: .distantPast
        )
    }
    #expect(throws: PokerSessionError.invalidBuyIn) {
        try ledger.cashOut(
            amount: try Chips(0),
            table: table,
            id: try BusinessID("zero-out"),
            at: .distantPast
        )
    }
    #expect(ledger.entries.isEmpty)
}

@Test func decodingRebuildsBusinessIndexAndPreservesIdempotency() throws {
    var ledger = EntertainmentChipLedger()
    let id = try BusinessID("buy-round-trip")
    let table = try TableID("jade")
    let timestamp = Date(timeIntervalSince1970: 42)
    let originalEntry = try ledger.buyIn(
        amount: try Chips(5_000), table: table, id: id, at: timestamp
    )

    let data = try JSONEncoder().encode(ledger)
    let decodedObject = try JSONSerialization.jsonObject(with: data)
    guard let object = decodedObject as? [String: Any] else {
        Issue.record("账本编码结果不是 JSON 对象")
        return
    }
    #expect(Set(object.keys) == ["balance", "entries"])

    var decoded = try JSONDecoder().decode(EntertainmentChipLedger.self, from: data)
    let repeated = try decoded.buyIn(
        amount: try Chips(5_000), table: table, id: id, at: .distantFuture
    )
    #expect(repeated == originalEntry)
    #expect(decoded.entries.count == 1)
}

@Test(arguments: CorruptLedgerFixture.all)
func decodingRejectsCorruptLedger(fixture: CorruptLedgerFixture) throws {
    let data = try JSONEncoder().encode(fixture.payload)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(EntertainmentChipLedger.self, from: data)
    }
}

struct LedgerPayload: Encodable, Sendable {
    let balance: Chips
    let entries: [LedgerEntry]
}

struct CorruptLedgerFixture: CustomTestStringConvertible, Sendable {
    let name: String
    let payload: LedgerPayload

    var testDescription: String { name }

    static let all: [Self] = makeFixtures()

    private static func makeFixtures() -> [Self] {
        let day = try! LocalDay("2026-07-14")
        let nextDay = try! LocalDay("2026-07-15")
        let table = try! TableID("jade")
        let firstID = try! BusinessID("first")
        let secondID = try! BusinessID("second")
        let thirdID = try! BusinessID("third")

        func entry(
            id: BusinessID,
            reason: LedgerReason,
            before: Int,
            delta: Int,
            after: Int
        ) -> LedgerEntry {
            LedgerEntry(
                businessID: id,
                timestamp: .distantPast,
                reason: reason,
                balanceBefore: try! Chips(before),
                delta: delta,
                balanceAfter: try! Chips(after)
            )
        }

        let validGift = entry(
            id: firstID,
            reason: .dailyGift(day: day),
            before: 1_000,
            delta: 10_000,
            after: 11_000
        )
        let validCashOut = entry(
            id: secondID,
            reason: .cashOut(table: table),
            before: 11_000,
            delta: 1_000,
            after: 12_000
        )

        return [
            Self(
                name: "流水前后余额链断裂",
                payload: LedgerPayload(
                    balance: try! Chips(13_000),
                    entries: [
                        validGift,
                        entry(
                            id: secondID,
                            reason: .cashOut(table: table),
                            before: 12_000,
                            delta: 1_000,
                            after: 13_000
                        ),
                    ]
                )
            ),
            Self(
                name: "最终余额不等于末条流水余额",
                payload: LedgerPayload(
                    balance: try! Chips(12_001), entries: [validGift, validCashOut]
                )
            ),
            Self(
                name: "重复业务编号",
                payload: LedgerPayload(
                    balance: try! Chips(12_000),
                    entries: [
                        validGift,
                        entry(
                            id: firstID,
                            reason: .cashOut(table: table),
                            before: 11_000,
                            delta: 1_000,
                            after: 12_000
                        ),
                    ]
                )
            ),
            Self(
                name: "买入流水金额符号错误",
                payload: LedgerPayload(
                    balance: try! Chips(2_000),
                    entries: [
                        entry(
                            id: firstID,
                            reason: .cashBuyIn(table: table),
                            before: 1_000,
                            delta: 1_000,
                            after: 2_000
                        ),
                    ]
                )
            ),
            Self(
                name: "退回流水金额符号错误",
                payload: LedgerPayload(
                    balance: try! Chips(1_000),
                    entries: [
                        entry(
                            id: firstID,
                            reason: .cashOut(table: table),
                            before: 2_000,
                            delta: -1_000,
                            after: 1_000
                        ),
                    ]
                )
            ),
            Self(
                name: "每日赠送不是固定金额",
                payload: LedgerPayload(
                    balance: try! Chips(10_999),
                    entries: [
                        entry(
                            id: firstID,
                            reason: .dailyGift(day: day),
                            before: 1_000,
                            delta: 9_999,
                            after: 10_999
                        ),
                    ]
                )
            ),
            Self(
                name: "每日赠送同日重复",
                payload: LedgerPayload(
                    balance: try! Chips(21_000),
                    entries: [
                        validGift,
                        entry(
                            id: secondID,
                            reason: .dailyGift(day: day),
                            before: 11_000,
                            delta: 10_000,
                            after: 21_000
                        ),
                    ]
                )
            ),
            Self(
                name: "救济金额不是正数",
                payload: LedgerPayload(
                    balance: try! Chips(20_000),
                    entries: [
                        entry(
                            id: firstID,
                            reason: .bankruptcyRelief(day: day),
                            before: 20_000,
                            delta: 0,
                            after: 20_000
                        ),
                    ]
                )
            ),
            Self(
                name: "救济后余额不是目标值",
                payload: LedgerPayload(
                    balance: try! Chips(19_999),
                    entries: [
                        entry(
                            id: firstID,
                            reason: .bankruptcyRelief(day: day),
                            before: 1_500,
                            delta: 18_499,
                            after: 19_999
                        ),
                    ]
                )
            ),
            Self(
                name: "救济前余额未低于领取阈值",
                payload: LedgerPayload(
                    balance: try! Chips(20_000),
                    entries: [
                        entry(
                            id: firstID,
                            reason: .bankruptcyRelief(day: day),
                            before: 19_000,
                            delta: 1_000,
                            after: 20_000
                        ),
                    ]
                )
            ),
            Self(
                name: "救济同日重复",
                payload: LedgerPayload(
                    balance: try! Chips(20_000),
                    entries: [
                        entry(
                            id: firstID,
                            reason: .bankruptcyRelief(day: day),
                            before: 1_500,
                            delta: 18_500,
                            after: 20_000
                        ),
                        entry(
                            id: secondID,
                            reason: .cashBuyIn(table: table),
                            before: 20_000,
                            delta: -19_000,
                            after: 1_000
                        ),
                        entry(
                            id: thirdID,
                            reason: .bankruptcyRelief(day: day),
                            before: 1_000,
                            delta: 19_000,
                            after: 20_000
                        ),
                    ]
                )
            ),
            Self(
                name: "整数加法溢出",
                payload: LedgerPayload(
                    balance: try! Chips(Int.max),
                    entries: [
                        entry(
                            id: firstID,
                            reason: .cashOut(table: table),
                            before: Int.max,
                            delta: 1,
                            after: Int.max
                        ),
                    ]
                )
            ),
            Self(
                name: "跨日赠送仍须保持余额链",
                payload: LedgerPayload(
                    balance: try! Chips(21_000),
                    entries: [
                        validGift,
                        entry(
                            id: secondID,
                            reason: .dailyGift(day: nextDay),
                            before: 11_000,
                            delta: 10_000,
                            after: 20_999
                        ),
                    ]
                )
            ),
        ]
    }
}
