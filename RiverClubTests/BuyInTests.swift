import XCTest
@testable import RiverClub

final class BuyInTests: XCTestCase {
    func testBuyInUsesFortyToOneHundredBigBlinds() {
        let range = BuyInRange(bigBlind: 400, balance: 128_500)

        XCTAssertEqual(range.minimum, 16_000)
        XCTAssertEqual(range.maximum, 40_000)
    }

    func testBuyInMaximumDoesNotExceedBalance() {
        let range = BuyInRange(bigBlind: 400, balance: 24_000)

        XCTAssertEqual(range.minimum, 16_000)
        XCTAssertEqual(range.maximum, 24_000)
    }

    func testBuyInClampsToTableRangeAndBalance() {
        var state = BuyInState(minimum: 2_000, maximum: 10_000, balance: 6_500)
        state.amount = 9_000
        state.normalize()
        XCTAssertEqual(state.amount, 6_500)
        XCTAssertTrue(state.canConfirm)
    }

    func testInsufficientBalanceCannotConfirm() {
        let state = BuyInState(minimum: 2_000, maximum: 10_000, balance: 1_500)
        XCTAssertFalse(state.canConfirm)
    }

    func testInsufficientBalanceDoesNotProduceSliderRange() {
        let state = BuyInState(minimum: 8_000, maximum: 5_000, balance: 5_000)

        XCTAssertNil(state.sliderRange)
    }

    func testExactMinimumUsesStaticTrackInsteadOfZeroLengthSlider() {
        let state = BuyInState(minimum: 8_000, maximum: 8_000, balance: 8_000)

        XCTAssertNil(state.sliderRange)
        XCTAssertTrue(state.canConfirm)
    }

    func testRangeShorterThanBlindStepUsesStaticTrack() {
        let state = BuyInState(minimum: 8_000, maximum: 8_100, balance: 8_100)

        XCTAssertNil(state.sliderRange(step: 200))
    }

    func testQuickJoinMatchesSelectedBlindWithAnOpenSeat() {
        let fullMatch = makeTable(name: "满桌", smallBlind: 100, bigBlind: 200, players: 9)
        let wrongBlind = makeTable(name: "其他盲注", smallBlind: 200, bigBlind: 400, players: 4)
        let openMatch = makeTable(name: "可加入", smallBlind: 100, bigBlind: 200, players: 8)

        let match = QuickJoinMatcher.match(
            in: [fullMatch, wrongBlind, openMatch],
            blind: .oneHundredTwoHundred
        )

        XCTAssertEqual(match, openMatch)
    }

    func testTableFiltersCombinePrimaryTypeSeatAndBlindRange() {
        let favoriteOpenLow = makeTable(
            name: "收藏低盲注",
            smallBlind: 100,
            bigBlind: 200,
            players: 8,
            isFavorite: true
        )
        let favoriteFullLow = makeTable(
            name: "收藏满桌",
            smallBlind: 100,
            bigBlind: 200,
            players: 9,
            isFavorite: true
        )
        let openLowNotFavorite = makeTable(
            name: "未收藏",
            smallBlind: 100,
            bigBlind: 200,
            players: 7
        )

        let filters = TableListFilters(
            primary: .favorites,
            tableType: .nineSeat,
            seatAvailability: .openSeats,
            blindRange: .low
        )

        XCTAssertEqual(
            filters.apply(to: [favoriteFullLow, openLowNotFavorite, favoriteOpenLow]),
            [favoriteOpenLow]
        )
    }

    func testFullTableUsesWaitlistInsteadOfBuyIn() {
        let fullTable = makeTable(name: "满桌", smallBlind: 100, bigBlind: 200, players: 9)

        XCTAssertEqual(JoinDisposition(table: fullTable), .waitlist)
    }

    private func makeTable(
        name: String,
        smallBlind: Int,
        bigBlind: Int,
        players: Int,
        isFavorite: Bool = false
    ) -> PokerTableSummary {
        PokerTableSummary(
            id: UUID(),
            name: name,
            smallBlind: smallBlind,
            bigBlind: bigBlind,
            players: players,
            capacity: 9,
            averagePot: 1_000,
            isFavorite: isFavorite
        )
    }
}
