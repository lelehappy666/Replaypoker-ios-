import CoreGraphics
import XCTest
@testable import RiverClub

final class PokerTableLayoutTests: XCTestCase {
    private let canvas = CGSize(width: 932, height: 424)

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

    func testAllSeatFramesStayOnScreenAndOutsideBetControlRegion() {
        let frames = seatFrames()
        let screenBounds = CGRect(origin: .zero, size: canvas)
        let betControlRegion = PokerTableLayout.betControlRegion(for: canvas)

        for (index, frame) in frames.enumerated() {
            XCTAssertTrue(screenBounds.contains(frame), "Seat \(index) is outside the screen: \(frame)")
            XCTAssertFalse(frame.intersects(betControlRegion), "Seat \(index) intersects bet controls: \(frame)")
        }
    }

    func testOpponentFramesDoNotIntersectEachOtherOrLocalPlayer() {
        let frames = seatFrames()

        for firstIndex in 0..<8 {
            for secondIndex in (firstIndex + 1)..<9 {
                XCTAssertFalse(
                    frames[firstIndex].intersects(frames[secondIndex]),
                    "Seats \(firstIndex) and \(secondIndex) intersect"
                )
            }
        }
    }

    private func seatFrames() -> [CGRect] {
        let positions = PokerTableLayout.positions(for: canvas)
        return positions.map { normalizedCenter in
            CGRect(
                x: normalizedCenter.x * canvas.width - PokerTableLayout.seatSize.width / 2,
                y: normalizedCenter.y * canvas.height - PokerTableLayout.seatSize.height / 2,
                width: PokerTableLayout.seatSize.width,
                height: PokerTableLayout.seatSize.height
            )
        }
    }
}
