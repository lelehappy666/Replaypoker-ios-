import XCTest

@MainActor
final class LandscapeLayoutUITests: XCTestCase {
    private let firstTableIdentifier = "tableRow.10000000-0000-0000-0000-000000000001"
    private let currencySymbols = ["¥", "$", "€", "£"]

    func testLandscapeTableLayoutAndEntertainmentChipCompliance() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        assertNoCurrencySymbols(in: app)
        app.buttons["login.guest"].tap()
        XCTAssertTrue(app.buttons["lobby.allTables"].waitForExistence(timeout: 5))
        assertNoCurrencySymbols(in: app)
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
        XCTAssertGreaterThan(window.frame.width, window.frame.height)

        let localSeat = app.otherElements["table.seat.8"]
        XCTAssertTrue(localSeat.waitForExistence(timeout: 5))
        for index in 0..<9 {
            let seat = app.otherElements["table.seat.\(index)"]
            XCTAssertTrue(seat.exists)
            XCTAssertTrue(seat.isHittable || !seat.frame.isEmpty)
            if index != 8 {
                XCTAssertFalse(seat.frame.intersects(localSeat.frame))
            }
        }

        let localAvatar = app.otherElements["table.localAvatar"]
        XCTAssertTrue(localAvatar.exists)
        XCTAssertLessThanOrEqual(abs(localAvatar.frame.width - localAvatar.frame.height), 1)
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
