import CoreGraphics
import XCTest
@testable import RiverClub

@MainActor
final class PokerTableLayoutTests: XCTestCase {
    func testApprovedDesignUsesSingleReferenceCanvasAndExactSeatAnchors() {
        XCTAssertEqual(PokerTableLayout.referenceCanvas, CGSize(width: 922, height: 426.5))
        XCTAssertEqual(
            PokerTableLayout.positions(for: PokerTableLayout.referenceCanvas),
            [
                CGPoint(x: 218, y: 75),
                CGPoint(x: 451, y: 72),
                CGPoint(x: 670, y: 74),
                CGPoint(x: 828, y: 202),
                CGPoint(x: 82, y: 170),
                CGPoint(x: 82, y: 269),
                CGPoint(x: 201, y: 340),
                CGPoint(x: 337, y: 348),
                CGPoint(x: 476, y: 350),
            ]
        )
        XCTAssertEqual(PokerTableLayout.betControlSize, CGSize(width: 265, height: 112))
        XCTAssertEqual(
            PokerTableLayout.tableSurfaceFrame(for: PokerTableLayout.referenceCanvas),
            CGRect(x: 65, y: 73, width: 760, height: 292)
        )
    }

    func testReferenceCanvasOnlyScalesUniformlyOnLandscapePhones() {
        for canvas in [
            CGSize(width: 844, height: 390),
            CGSize(width: 932, height: 424),
            CGSize(width: 956, height: 440),
        ] {
            let scale = PokerTableLayout.referenceScale(for: canvas)
            let seat = PokerTableLayout.seatFrameSize(for: canvas)
            let bounds = CGRect(origin: .zero, size: canvas)
            XCTAssertEqual(seat.width, PokerTableLayout.seatSize.width * scale, accuracy: 0.001)
            XCTAssertEqual(seat.height, PokerTableLayout.seatSize.height * scale, accuracy: 0.001)
            XCTAssertEqual(PokerTableLayout.positions(for: canvas).count, 9)
            XCTAssertTrue(bounds.contains(PokerTableLayout.tableSurfaceFrame(for: canvas)))
            XCTAssertTrue(bounds.contains(PokerTableLayout.betControlRegion(for: canvas)))
        }
    }

    func testApprovedCardMetricsMatchReferenceArtwork() {
        XCTAssertEqual(PokerTableLayout.communityCardSize, CGSize(width: 50, height: 56))
        XCTAssertEqual(PokerTableLayout.humanHoleCardSize, CGSize(width: 38, height: 50))
        XCTAssertEqual(PokerTableLayout.botHoleCardSize, CGSize(width: 28, height: 38))
        XCTAssertEqual(PokerTableLayout.holeCardSpacing, 7)
    }

    func testPayoutMovesFromPotToWinnerSeat() {
        let canvas = PokerTableLayout.referenceCanvas
        let pot = PokerTableLayout.potFrame(for: canvas)
        let seats = PokerTableLayout.positions(for: canvas)

        for index in seats.indices {
            let start = PokerTableLayout.payoutPosition(
                toSeatAt: index,
                canvas: canvas,
                progress: 0
            )
            let end = PokerTableLayout.payoutPosition(
                toSeatAt: index,
                canvas: canvas,
                progress: 1
            )
            XCTAssertEqual(start, CGPoint(x: pot.midX, y: pot.midY))
            XCTAssertEqual(end, seats[index])
        }
    }

    func testPlayableTableExposesDepartureControl() throws {
        let source = try String(
            contentsOfFile: #filePath.replacingOccurrences(
                of: "RiverClubTests/PokerTableLayoutTests.swift",
                with: "RiverClub/Features/Table/PokerTableView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("table.leave"))
        XCTAssertTrue(source.contains("onRequestLeave"))
    }
}
