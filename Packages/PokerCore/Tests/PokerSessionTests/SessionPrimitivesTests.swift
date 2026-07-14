import Foundation
import PokerCore
import Testing
@testable import PokerSession

@Test func economyConstantsMatchApprovedDesign() throws {
    #expect(SessionEconomy.initialBalance == (try Chips(128_500)))
    #expect(SessionEconomy.dailyGift == (try Chips(10_000)))
    #expect(SessionEconomy.reliefThreshold == (try Chips(2_000)))
    #expect(SessionEconomy.reliefTarget == (try Chips(20_000)))
    #expect(SessionEconomy.minimumBuyInBigBlinds == 40)
    #expect(SessionEconomy.maximumBuyInBigBlinds == 100)
}

@Test func identifiersRejectEmptyOrWhitespaceValues() {
    #expect(throws: PokerSessionError.invalidIdentifier) { try BusinessID("  ") }
    #expect(throws: PokerSessionError.invalidIdentifier) { try HandID("") }
}

@Test func identifiersRejectInvalidCodableValues() {
    let invalid = Data(#"" \n ""#.utf8)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(BusinessID.self, from: invalid)
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(SessionID.self, from: invalid)
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(HandID.self, from: invalid)
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(TableID.self, from: invalid)
    }
}

@Test func localDayRejectsNonexistentGregorianDates() {
    #expect(throws: PokerSessionError.invalidIdentifier) { try LocalDay("2026-02-29") }
    #expect(throws: PokerSessionError.invalidIdentifier) { try LocalDay("2026-04-31") }
}

@Test func localDayRejectsNonCanonicalFormats() {
    #expect(throws: PokerSessionError.invalidIdentifier) { try LocalDay("-2026-07-14") }
    #expect(throws: PokerSessionError.invalidIdentifier) { try LocalDay("2026--07-14") }
    #expect(throws: PokerSessionError.invalidIdentifier) { try LocalDay("2026-07-14-") }
}

@Test func localDayRejectsInvalidCodableValue() {
    let invalid = Data(#""2026-02-29""#.utf8)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(LocalDay.self, from: invalid)
    }
}

@Test func fixedClockProvidesStableMomentAndLocalDay() throws {
    let instant = Date(timeIntervalSince1970: 1_720_915_200)
    let clock = FixedSessionClock(now: instant, day: try LocalDay("2026-07-14"))
    #expect(clock.now == instant)
    #expect(clock.currentDay == (try LocalDay("2026-07-14")))
}
