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
}
