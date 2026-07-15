import CoreGraphics
import XCTest
@testable import RiverClub

final class PokerTableLayoutTests: XCTestCase {
    private let canvases = [
        CGSize(width: 780, height: 360),
        CGSize(width: 844, height: 390),
        CGSize(width: 932, height: 424),
    ]

    func testNineSeatsAdaptToMultipleSafeCanvasSizes() {
        for canvas in canvases {
            let positions = PokerTableLayout.positions(for: canvas)
            XCTAssertEqual(positions.count, 9)
            XCTAssertEqual(Set(positions.map { "\($0.x),\($0.y)" }).count, 9)

            let safeCanvas = PokerTableLayout.safeCanvas(for: canvas)
            let reservedRegions = [
                PokerTableLayout.betControlRegion(for: canvas),
                PokerTableLayout.topBarRegion(for: canvas),
                PokerTableLayout.centerBoardRegion(for: canvas),
            ]
            let frames = PokerTableLayout.seatFrames(for: canvas)

            for (index, frame) in frames.enumerated() {
                XCTAssertTrue(safeCanvas.contains(frame), "Seat \(index) outside \(canvas)")
                for region in reservedRegions {
                    XCTAssertFalse(frame.intersects(region), "Seat \(index) intersects \(region)")
                }
            }

            for first in 0..<frames.count {
                for second in (first + 1)..<frames.count {
                    XCTAssertFalse(frames[first].intersects(frames[second]))
                }
            }
        }
    }

    func testLocalPlayerIsCenteredAtBottomOfEachCanvas() {
        for canvas in canvases {
            let local = PokerTableLayout.positions(for: canvas)[8]
            XCTAssertEqual(local.x, canvas.width * 0.5, accuracy: 0.001)
            XCTAssertGreaterThan(local.y, canvas.height * 0.8)
        }
    }

    func testActionRegionKeepsApprovedLandscapeFootprint() {
        XCTAssertEqual(PokerTableLayout.seatSize.width, 108)
        XCTAssertEqual(PokerTableLayout.seatSize.height, 96)
        XCTAssertEqual(PokerTableLayout.betControlSize.width, 330)
        XCTAssertEqual(PokerTableLayout.betControlSize.height, 164)
    }

    func testPlayableTableDoesNotExposeBackOrExitControl() throws {
        let source = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(of: "RiverClubTests/PokerTableLayoutTests.swift", with: "RiverClub/Features/Table/PokerTableView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("Label(\"返回\""))
        XCTAssertFalse(source.contains("onExit"))
    }
}
