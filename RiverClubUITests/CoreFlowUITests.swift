import XCTest

@MainActor
final class CoreFlowUITests: XCTestCase {
    private let firstTableIdentifier = "tableRow.10000000-0000-0000-0000-000000000001"

    func testGuestCanCompleteHandAndStartNextHand() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingImmediatePoker"]
        app.launch()

        let guestLogin = app.buttons["login.guest"]
        XCTAssertTrue(guestLogin.waitForExistence(timeout: 5))
        guestLogin.tap()
        XCTAssertTrue(app.buttons["lobby.allTables"].waitForExistence(timeout: 5))
        app.buttons["lobby.allTables"].tap()

        let firstTable = app.buttons[firstTableIdentifier]
        XCTAssertTrue(firstTable.waitForExistence(timeout: 5))
        firstTable.tap()

        let slider = app.sliders["buyIn.slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        slider.adjust(toNormalizedSliderPosition: 0.25)
        app.buttons["buyIn.confirm"].tap()

        let safeCanvas = app.otherElements["table.safeCanvas"]
        XCTAssertTrue(safeCanvas.waitForExistence(timeout: 5))
        let firstHandID = try XCTUnwrap(safeCanvas.value as? String)
        XCTAssertFalse(firstHandID.isEmpty)

        for index in 0..<9 {
            XCTAssertTrue(
                app.otherElements["table.seat.\(index)"].waitForExistence(timeout: 5),
                "缺少第 \(index) 个座位"
            )
        }
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "table.localHoleCard")
                .count,
            2
        )

        let fold = app.buttons["action.fold"]
        XCTAssertTrue(fold.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.buttons["action.middle"].exists || app.buttons["action.aggressive"].exists
        )
        fold.tap()

        let nextHand = app.buttons["action.nextHand"]
        XCTAssertTrue(nextHand.waitForExistence(timeout: 15))
        nextHand.tap()
        expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: nextHand
        )
        expectation(
            for: NSPredicate(format: "value != %@", firstHandID),
            evaluatedWith: safeCanvas
        )
        waitForExpectations(timeout: 10)
        XCTAssertNotEqual(safeCanvas.value as? String, firstHandID)
        XCTAssertTrue(app.buttons["action.fold"].waitForExistence(timeout: 10))
    }
}
