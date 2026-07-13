import XCTest

@MainActor
final class CoreFlowUITests: XCTestCase {
    private let firstTableIdentifier = "tableRow.10000000-0000-0000-0000-000000000001"

    func testGuestCanBuyInAndReachNineSeatTable() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        app.buttons["login.guest"].tap()
        XCTAssertTrue(app.buttons["lobby.allTables"].waitForExistence(timeout: 5))
        app.buttons["lobby.allTables"].tap()

        let firstTable = app.buttons[firstTableIdentifier]
        XCTAssertTrue(firstTable.waitForExistence(timeout: 5))
        firstTable.tap()

        let slider = app.sliders["buyIn.slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        slider.adjust(toNormalizedSliderPosition: 0.25)
        app.buttons["buyIn.confirm"].tap()

        for index in 0..<9 {
            XCTAssertTrue(
                app.otherElements["table.seat.\(index)"].waitForExistence(timeout: 5),
                "缺少第 \(index) 个座位"
            )
        }
        XCTAssertTrue(app.staticTexts["table.pot"].exists)
        XCTAssertTrue(app.buttons["action.fold"].exists)
        XCTAssertTrue(app.buttons["action.call"].exists)
        XCTAssertTrue(app.buttons["action.raise"].exists)
    }
}
