import XCTest

@MainActor
final class CoreFlowUITests: XCTestCase {
    private let firstTableIdentifier = "tableRow.10000000-0000-0000-0000-000000000001"

    func testGuestCanCompleteHandAndStartNextHand() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-uiTestingImmediatePoker",
            "-resetHistoryStore",
            "-uiTestingStoreID",
            "core-flow-complete-next",
        ]
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

    func testBotIdentitiesRemainStableUntilNextHandAndChangeOnlyAfterLeaving() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-uiTestingImmediatePoker",
            "-resetHistoryStore",
            "-uiTestingStoreID",
            "identity-lifecycle",
            "-uiTestingIdentitySeed",
            "41",
        ]
        app.launch()

        enterFirstTable(in: app)
        let first = botIdentityValues(in: app)

        let fold = app.buttons["action.fold"]
        XCTAssertTrue(fold.waitForExistence(timeout: 10))
        fold.tap()
        let nextHand = app.buttons["action.nextHand"]
        XCTAssertTrue(nextHand.waitForExistence(timeout: 15))
        nextHand.tap()
        XCTAssertTrue(app.buttons["action.fold"].waitForExistence(timeout: 10))
        XCTAssertEqual(botIdentityValues(in: app), first)

        app.buttons["table.leave"].tap()
        XCTAssertTrue(app.buttons["table.leave.confirm"].waitForExistence(timeout: 5))
        app.buttons["table.leave.confirm"].tap()
        XCTAssertTrue(app.buttons[firstTableIdentifier].waitForExistence(timeout: 15))
        app.buttons[firstTableIdentifier].tap()
        XCTAssertTrue(app.sliders["buyIn.slider"].waitForExistence(timeout: 5))
        app.buttons["buyIn.confirm"].tap()

        let reentered = botIdentityValues(in: app)
        XCTAssertEqual(reentered.count, 8)
        XCTAssertEqual(Set(reentered).count, 8)
        XCTAssertNotEqual(reentered, first)
    }

    func testSinglePayoutAnnouncementIsPresentedExactlyOnce() throws {
        let app = launchPayoutScenario("single", storeID: "payout-single")
        enterFirstTable(in: app)

        let records = payoutRecords(in: app, expectedCount: 1)
        XCTAssertEqual(records, ["4|\(displayName(in: app, forSeat: 4))|800"])
    }

    func testSplitPayoutAnnouncementsPreserveInputOrderWithoutDuplicates() throws {
        let app = launchPayoutScenario("split", storeID: "payout-split")
        enterFirstTable(in: app)

        let records = payoutRecords(in: app, expectedCount: 2)
        XCTAssertEqual(records, [
            "2|\(displayName(in: app, forSeat: 2))|250",
            "8|RiverAce|500",
        ])
        XCTAssertEqual(Set(records).count, 2)
    }

    private func enterFirstTable(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["login.guest"].waitForExistence(timeout: 5))
        app.buttons["login.guest"].tap()
        XCTAssertTrue(app.buttons["lobby.allTables"].waitForExistence(timeout: 5))
        app.buttons["lobby.allTables"].tap()
        XCTAssertTrue(app.buttons[firstTableIdentifier].waitForExistence(timeout: 5))
        app.buttons[firstTableIdentifier].tap()
        XCTAssertTrue(app.sliders["buyIn.slider"].waitForExistence(timeout: 5))
        app.buttons["buyIn.confirm"].tap()
        XCTAssertTrue(app.otherElements["table.safeCanvas"].waitForExistence(timeout: 5))
    }

    private func botIdentityValues(in app: XCUIApplication) -> [String] {
        let avatars = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'table.botAvatar.'"))
            .allElementsBoundByIndex
            .sorted { $0.identifier < $1.identifier }
        XCTAssertEqual(avatars.count, 8)
        let values = avatars.compactMap { $0.value as? String }
        XCTAssertEqual(values.count, 8)
        XCTAssertEqual(Set(values).count, 8)
        return values
    }

    private func launchPayoutScenario(
        _ scenario: String,
        storeID: String
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-uiTestingImmediatePoker",
            "-resetHistoryStore",
            "-uiTestingStoreID",
            storeID,
            "-uiTestingPayoutScenario",
            scenario,
            "-uiTestingPayoutLog",
            "-uiTestingIdentitySeed",
            "41",
        ]
        app.launch()
        return app
    }

    private func payoutRecords(
        in app: XCUIApplication,
        expectedCount: Int
    ) -> [String] {
        let log = app.otherElements["table.uiTestingPayoutLog"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        let expected = expectedCount == 1
            ? NSPredicate(format: "value != ''")
            : NSPredicate(format: "value CONTAINS ','")
        expectation(for: expected, evaluatedWith: log)
        waitForExpectations(timeout: 5)
        let records = (log.value as? String ?? "")
            .split(separator: ",")
            .map(String.init)
        XCTAssertEqual(records.count, expectedCount)
        return records
    }

    private func displayName(in app: XCUIApplication, forSeat seat: Int) -> String {
        let avatar = app.descendants(matching: .any)["table.botAvatar.\(seat)"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 5))
        return avatar.value as? String ?? ""
    }
}
