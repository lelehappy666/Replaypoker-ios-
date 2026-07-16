import XCTest

@MainActor
final class TableDepartureUITests: XCTestCase {
    private let firstTableIdentifier =
        "tableRow.10000000-0000-0000-0000-000000000001"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDepartureCanBeCancelledThenConfirmedAndReturnsToTableBrowser() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-uiTestingImmediatePoker",
            "-resetHistoryStore",
            "-uiTestingStoreID",
            "table-departure-flow",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["login.guest"].waitForExistence(timeout: 5))
        app.buttons["login.guest"].tap()
        XCTAssertTrue(app.buttons["lobby.allTables"].waitForExistence(timeout: 5))
        app.buttons["lobby.allTables"].tap()

        let firstTable = app.buttons[firstTableIdentifier]
        XCTAssertTrue(firstTable.waitForExistence(timeout: 5))
        firstTable.tap()
        XCTAssertTrue(app.sliders["buyIn.slider"].waitForExistence(timeout: 3))
        app.sliders["buyIn.slider"].adjust(toNormalizedSliderPosition: 0.25)
        app.buttons["buyIn.confirm"].tap()

        let leave = app.buttons["table.leave"]
        XCTAssertTrue(leave.waitForExistence(timeout: 5))
        leave.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["table.leave.confirmation"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["table.leave.cancel"].tap()
        XCTAssertTrue(leave.waitForExistence(timeout: 3))

        leave.tap()
        let confirm = app.buttons["table.leave.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        XCTAssertTrue(firstTable.waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["table.safeCanvas"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["table.leave.confirmation"].exists
        )
    }
}
