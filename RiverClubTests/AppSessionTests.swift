import XCTest
@testable import RiverClub

final class AppSessionTests: XCTestCase {
    func testSidebarRoutesAreStable() {
        XCTAssertEqual(AppRoute.sidebarRoutes, [.lobby, .tournaments, .tables, .profile])
    }

    @MainActor
    func testGuestLoginOpensLobbyAndLogoutReturnsToLogin() {
        let session = AppSession()
        XCTAssertEqual(session.route, .login)
        session.continueAsGuest()
        XCTAssertEqual(session.route, .lobby)
        session.logout()
        XCTAssertEqual(session.route, .login)
    }

    @MainActor
    func testEnteringTableStoresSelectedTable() {
        let session = AppSession()
        let table = makeTable(name: "星河湾", smallBlind: 200, bigBlind: 400)

        session.enterTable(table)

        XCTAssertEqual(session.route, .table)
        XCTAssertEqual(session.selectedTable, table)
    }

    func testTableHeaderUsesSelectedTableNameAndBlinds() {
        let table = makeTable(name: "星河湾", smallBlind: 200, bigBlind: 400)

        XCTAssertEqual(PokerTablePresentation.title(for: table), "星河湾 · 200 / 400")
    }

    @MainActor
    func testLeavingTableClearsSelectedTableAndRestoresRoute() {
        let session = AppSession()
        session.enterTable(makeTable(name: "星河湾", smallBlind: 200, bigBlind: 400))

        session.leaveTable(returningTo: .tables)

        XCTAssertEqual(session.route, .tables)
        XCTAssertNil(session.selectedTable)
    }

    private func makeTable(name: String, smallBlind: Int, bigBlind: Int) -> PokerTableSummary {
        PokerTableSummary(
            id: UUID(),
            name: name,
            smallBlind: smallBlind,
            bigBlind: bigBlind,
            players: 6,
            capacity: 9,
            averagePot: 1_200,
            isFavorite: false
        )
    }
}
