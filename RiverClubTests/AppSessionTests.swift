import XCTest
@testable import RiverClub

final class AppSessionTests: XCTestCase {
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
