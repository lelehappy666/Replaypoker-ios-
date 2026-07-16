import XCTest

@MainActor
final class HandHistoryFlowUITests: XCTestCase {
    private let firstTableIdentifier =
        "tableRow.10000000-0000-0000-0000-000000000001"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCompletedHandAppearsWithFoldedCardsAndCanBeDeleted() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-uiTestingImmediatePoker",
            "-resetHistoryStore",
        ]
        app.launch()

        let guestLogin = app.buttons["login.guest"]
        XCTAssertTrue(guestLogin.waitForExistence(timeout: 5))
        guestLogin.tap()

        let allTables = app.buttons["lobby.allTables"]
        XCTAssertTrue(allTables.waitForExistence(timeout: 5))
        allTables.tap()

        let firstTable = app.buttons[firstTableIdentifier]
        XCTAssertTrue(firstTable.waitForExistence(timeout: 5))
        firstTable.tap()

        let slider = app.sliders["buyIn.slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        slider.adjust(toNormalizedSliderPosition: 0.25)
        app.buttons["buyIn.confirm"].tap()

        let fold = app.buttons["action.fold"]
        XCTAssertTrue(fold.waitForExistence(timeout: 10))
        fold.tap()
        XCTAssertTrue(app.buttons["action.nextHand"].waitForExistence(timeout: 15))

        app.terminate()
        app.launchArguments = [
            "-uiTesting",
            "-uiTestingImmediatePoker",
            "-openHistory",
        ]
        app.launch()

        let balance = app.staticTexts["history.balance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        let balanceBefore = balance.label
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.row.'")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.scrollViews["history.detail"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.otherElements.matching(
                NSPredicate(format: "identifier BEGINSWITH 'history.seat.'")
            ).count,
            9
        )
        XCTAssertGreaterThan(
            app.otherElements.matching(
                NSPredicate(format: "identifier BEGINSWITH 'history.holeCard.'")
            ).count,
            2
        )

        app.buttons["history.deleteOne"].tap()
        let confirmDelete = app.buttons["history.confirmDeleteOne"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertTrue(app.otherElements["history.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["history.balance"].label, balanceBefore)
    }
}
