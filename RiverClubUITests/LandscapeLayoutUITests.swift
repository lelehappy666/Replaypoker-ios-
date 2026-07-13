import XCTest

@MainActor
final class LandscapeLayoutUITests: XCTestCase {
    private let firstTableIdentifier = "tableRow.10000000-0000-0000-0000-000000000001"
    private let currencySymbols = ["¥", "$", "€", "£"]

    func testLandscapeTableLayoutAndEntertainmentChipCompliance() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let guestLogin = app.buttons["login.guest"]
        XCTAssertTrue(guestLogin.waitForExistence(timeout: 5))
        assertNoCurrencySymbols(in: app)
        guestLogin.tap()
        XCTAssertTrue(app.buttons["lobby.allTables"].waitForExistence(timeout: 5))
        assertNoCurrencySymbols(in: app)

        let tournamentsNavigation = app.buttons["sidebar.tournaments"]
        XCTAssertTrue(tournamentsNavigation.exists)
        tournamentsNavigation.tap()
        for state in ["upcoming", "registered", "active", "finished"] {
            let tab = app.buttons["tournaments.tab.\(state)"]
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            tab.tap()
            assertNoCurrencySymbols(in: app)
        }

        let profileNavigation = app.buttons["sidebar.profile"]
        XCTAssertTrue(profileNavigation.exists)
        profileNavigation.tap()
        XCTAssertTrue(app.staticTexts["profile.nickname"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["profile.settings"].exists)
        for setting in ["牌局记录", "成就徽章", "账户与安全", "声音与震动"] {
            XCTAssertTrue(app.buttons[setting].exists)
        }
        assertNoCurrencySymbols(in: app)

        let lobbyNavigation = app.buttons["sidebar.lobby"]
        XCTAssertTrue(lobbyNavigation.exists)
        lobbyNavigation.tap()
        XCTAssertTrue(app.buttons["lobby.allTables"].waitForExistence(timeout: 5))
        app.buttons["lobby.allTables"].tap()

        let firstTable = app.buttons[firstTableIdentifier]
        XCTAssertTrue(firstTable.waitForExistence(timeout: 5))
        assertNoCurrencySymbols(in: app)
        firstTable.tap()
        XCTAssertTrue(app.sliders["buyIn.slider"].waitForExistence(timeout: 3))
        assertNoCurrencySymbols(in: app)
        app.buttons["buyIn.confirm"].tap()

        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let windowFrame = window.frame
        XCTAssertFalse(windowFrame.isEmpty)
        XCTAssertGreaterThan(windowFrame.width, windowFrame.height)

        let localSeat = app.otherElements["table.seat.8"]
        XCTAssertTrue(localSeat.waitForExistence(timeout: 5))
        for index in 0..<9 {
            let seat = app.otherElements["table.seat.\(index)"]
            XCTAssertTrue(seat.exists)
            let seatFrame = seat.frame
            XCTAssertFalse(seatFrame.isEmpty)
            XCTAssertGreaterThan(seatFrame.width, 0)
            XCTAssertGreaterThan(seatFrame.height, 0)
            XCTAssertTrue(windowFrame.contains(seatFrame), "第 \(index) 个座位超出窗口")
            if index != 8 {
                XCTAssertFalse(seatFrame.intersects(localSeat.frame))
            }
        }

        let localAvatar = app.otherElements["table.localAvatar"]
        XCTAssertTrue(localAvatar.waitForExistence(timeout: 5))
        let avatarFrame = localAvatar.frame
        XCTAssertFalse(avatarFrame.isEmpty)
        XCTAssertGreaterThan(avatarFrame.width, 0)
        XCTAssertGreaterThan(avatarFrame.height, 0)
        XCTAssertLessThanOrEqual(abs(avatarFrame.width - avatarFrame.height), 1)
        assertNoCurrencySymbols(in: app)
    }

    private func assertNoCurrencySymbols(in app: XCUIApplication) {
        for text in app.staticTexts.allElementsBoundByIndex {
            for symbol in currencySymbols {
                XCTAssertFalse(text.label.contains(symbol), "发现真实货币符号：\(symbol)")
            }
        }
    }
}
