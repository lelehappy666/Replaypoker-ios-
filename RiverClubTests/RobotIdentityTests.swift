import XCTest
@testable import RiverClub

@MainActor
final class RobotIdentityTests: XCTestCase {
    func testCatalogContainsTwentyFourUniqueBoundIdentities() {
        let values = RobotIdentityCatalog.all

        XCTAssertEqual(values.count, 24)
        XCTAssertEqual(Set(values.map(\.id)).count, 24)
        XCTAssertEqual(Set(values.map(\.displayName)).count, 24)
        XCTAssertEqual(Set(values.map(\.avatarAssetName)).count, 24)
        XCTAssertTrue(values.allSatisfy { !$0.sourceURL.absoluteString.isEmpty })
        XCTAssertTrue(values.allSatisfy { !$0.photographer.isEmpty })
        XCTAssertTrue(values.allSatisfy { !$0.accessibilityDescription.isEmpty })
    }

    func testDrawReturnsEightUniqueIdentitiesDeterministically() {
        var a = SeededIdentityGenerator(seed: 41)
        var b = SeededIdentityGenerator(seed: 41)

        let left = RobotIdentityCatalog.draw(count: 8, using: &a)
        let right = RobotIdentityCatalog.draw(count: 8, using: &b)

        XCTAssertEqual(left, right)
        XCTAssertEqual(left.count, 8)
        XCTAssertEqual(Set(left.map(\.id)).count, 8)
    }

    func testPreviewIsStableAndUniqueForTheSameTableIdentifier() {
        let first = RobotIdentityCatalog.preview(for: "table-001", count: 6)
        let second = RobotIdentityCatalog.preview(for: "table-001", count: 6)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 6)
        XCTAssertEqual(Set(first.map(\.id)).count, 6)
    }
}

private struct SeededIdentityGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
