import PokerCoordinator
import XCTest
@testable import RiverClub

final class CashTableEntryTests: XCTestCase {
    @MainActor
    func testFailedSitDownKeepsBalanceAndRoute() throws {
        let fixture = try AppSessionFixture(failingSave: true)
        fixture.session.continueAsGuest()
        let before = fixture.session.chipBalance

        XCTAssertThrowsError(
            try fixture.session.joinCashTable(
                fixture.table,
                buyIn: 16_000,
                autoTopUp: false,
                reduceMotion: true
            )
        )

        XCTAssertEqual(fixture.session.chipBalance, before)
        XCTAssertEqual(fixture.session.route, .lobby)
        XCTAssertNil(fixture.session.tableCoordinator)
        XCTAssertNil(fixture.session.selectedTable)
    }

    @MainActor
    func testSuccessfulSitDownDeductsStoreBalanceAndEntersTable() throws {
        let fixture = try AppSessionFixture()
        fixture.session.continueAsGuest()
        let before = fixture.session.chipBalance

        try fixture.session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )

        XCTAssertEqual(fixture.session.chipBalance, before - 16_000)
        XCTAssertEqual(fixture.session.route, .table)
        XCTAssertEqual(fixture.session.selectedTable, fixture.table)
        XCTAssertNotNil(fixture.session.tableCoordinator)
    }

    func testNineProfilesAreUniqueAndMatchRequestSeats() throws {
        let table = AppSessionFixture.makeTable()
        let request = try CashTableRequestFactory.make(table: table, buyIn: 16_000)
        let profiles = try TableSeatProfileFactory.make(humanSeat: request.humanSeat)

        XCTAssertEqual(request.stacks.count, 9)
        XCTAssertEqual(profiles.count, 9)
        XCTAssertEqual(Set(profiles.map(\.id)), Set(request.stacks.keys))
        XCTAssertEqual(Set(profiles.map(\.displayName)).count, 9)
    }

    @MainActor
    func testInvalidProfilesAreRejectedBeforeSitDownWithoutChangingState() throws {
        let request = try CashTableRequestFactory.make(
            table: AppSessionFixture.makeTable(),
            buyIn: 16_000
        )
        let profiles = try TableSeatProfileFactory.make(humanSeat: request.humanSeat)
        let duplicateSeat = Array(profiles.dropLast()) + [profiles[0]]
        let duplicateName = try profiles.map { profile -> TableSeatProfile in
            if profile.id == request.humanSeat {
                return try TableSeatProfile(
                    id: profile.id,
                    displayName: profiles[0].displayName
                )
            }
            return profile
        }
        let invalidCases = [Array(profiles.dropLast()), duplicateSeat, duplicateName]

        for invalidProfiles in invalidCases {
            let fixture = try AppSessionFixture()
            fixture.session.continueAsGuest()
            let before = fixture.session.chipBalance

            XCTAssertThrowsError(
                try fixture.session.joinCashTable(
                    fixture.table,
                    buyIn: 16_000,
                    autoTopUp: false,
                    reduceMotion: true,
                    seatProfiles: invalidProfiles
                )
            )
            XCTAssertEqual(fixture.session.chipBalance, before)
            XCTAssertNil(fixture.store.cashSession)
            XCTAssertEqual(fixture.session.route, .lobby)
            XCTAssertNil(fixture.session.tableCoordinator)
        }
    }
}
