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
}
