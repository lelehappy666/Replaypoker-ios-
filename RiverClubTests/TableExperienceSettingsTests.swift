import XCTest
@testable import RiverClub

final class TableExperienceSettingsTests: XCTestCase {
    func testSettingsRoundTripKeepsAnimationSpeedAndSwitches() throws {
        let repository = MemoryTableExperienceSettingsRepository()
        let settings = TableExperienceSettings(
            chipAnimationEnabled: true,
            speed: .fast,
            currentHandHintEnabled: false,
            autoTopUpEnabled: true
        )

        try repository.save(settings)

        XCTAssertEqual(try repository.load(), settings)
        XCTAssertLessThan(TableAnimationSpeed.fast.durationMultiplier, 1)
        XCTAssertGreaterThan(TableAnimationSpeed.slow.durationMultiplier, 1)
    }

    func testMissingSettingsUseRecommendedDefaults() throws {
        let repository = MemoryTableExperienceSettingsRepository()

        XCTAssertEqual(try repository.load(), .recommended)
    }

    @MainActor
    func testAppSessionSavesTableSettingsAndAppliesThemImmediately() throws {
        let session = try AppSessionFixture().session
        let settings = TableExperienceSettings(
            chipAnimationEnabled: false,
            speed: .fast,
            currentHandHintEnabled: false,
            autoTopUpEnabled: true
        )

        try session.saveTableExperienceSettings(settings)

        XCTAssertEqual(session.tableExperienceSettings, settings)
        XCTAssertNil(session.tableExperienceSettingsError)
    }
}
