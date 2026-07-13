import CoreGraphics
import XCTest
@testable import RiverClub

final class PokerTableLayoutTests: XCTestCase {
    private let canvas = CGSize(width: 956, height: 440)

    func testNineSeatLayoutUsesDistinctNormalizedCenters() {
        let positions = PokerTableLayout.positions(for: canvas)

        XCTAssertEqual(positions.count, 9)
        XCTAssertEqual(Set(positions.map { "\($0.x),\($0.y)" }).count, 9)
        XCTAssertTrue(positions.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }

    func testLocalPlayerIsCenteredBelowTable() {
        let localPlayer = PokerTableLayout.positions(for: canvas)[8]

        XCTAssertEqual(localPlayer.x, 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(localPlayer.y, 0.8)
    }

    func testOpponentFramesDoNotIntersectLocalPlayerFrame() {
        let positions = PokerTableLayout.positions(for: canvas)
        let seatSize = CGSize(width: 96, height: 72)
        let frames = positions.map { normalizedCenter in
            CGRect(
                x: normalizedCenter.x * canvas.width - seatSize.width / 2,
                y: normalizedCenter.y * canvas.height - seatSize.height / 2,
                width: seatSize.width,
                height: seatSize.height
            )
        }

        for opponentFrame in frames.dropLast() {
            XCTAssertFalse(opponentFrame.intersects(frames[8]))
        }
    }
}
