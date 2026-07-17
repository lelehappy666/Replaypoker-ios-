import CoreGraphics
import XCTest
@testable import RiverClub

@MainActor
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
        XCTAssertEqual(PokerTableLayout.betControlSize.width, 260)
        XCTAssertEqual(PokerTableLayout.betControlSize.height, 128)
    }

    func testApprovedLandscapeCardAndSidebarMetrics() {
        XCTAssertLessThanOrEqual(AppSidebar.landscapePhoneWidth, 168)
        XCTAssertEqual(PokerTableLayout.communityCardSize, CGSize(width: 46, height: 62))
        XCTAssertEqual(PokerTableLayout.humanHoleCardSize, CGSize(width: 46, height: 62))
        XCTAssertEqual(PokerTableLayout.botHoleCardSize, CGSize(width: 38, height: 52))
    }

    func testCardsUsePokerRatioAndPositiveGap() {
        XCTAssertEqual(PokerTableLayout.cardAspectRatio, 34.0 / 46.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(PokerTableLayout.holeCardSpacing, 4)
    }

    func testFiveCommunitySlotsRemainClear() {
        for canvas in canvases {
            let slots = PokerTableLayout.communityCardFrames(for: canvas)
            XCTAssertEqual(slots.count, 5)

            for seat in PokerTableLayout.seatFrames(for: canvas) {
                XCTAssertTrue(slots.allSatisfy { !$0.intersects(seat) })
            }

            let operation = PokerTableLayout.betControlRegion(for: canvas)
            XCTAssertTrue(slots.allSatisfy { !$0.intersects(operation) })
        }
    }

    func testBetPositionsStayBetweenSeatAndTableCenterWithoutInvadingReservedAreas() {
        for canvas in canvases {
            let center = PokerTableLayout.tableCenter(for: canvas)
            let seatFrames = PokerTableLayout.seatFrames(for: canvas)
            let slots = PokerTableLayout.communityCardFrames(for: canvas)
            let operation = PokerTableLayout.betControlRegion(for: canvas)

            for index in seatFrames.indices {
                let position = PokerTableLayout.betPosition(forSeatAt: index, canvas: canvas)
                let seatCenter = CGPoint(x: seatFrames[index].midX, y: seatFrames[index].midY)

                XCTAssertLessThan(position.distance(to: center), seatCenter.distance(to: center))
                XCTAssertFalse(seatFrames[index].contains(position))
                XCTAssertFalse(operation.contains(position))
                XCTAssertTrue(slots.allSatisfy { !$0.contains(position) })
            }
        }
    }

    func testSeatsBetsAndOperationRegionRemainInBoundsAndSeparate() {
        for canvas in canvases {
            let safeCanvas = PokerTableLayout.safeCanvas(for: canvas)
            let seatFrames = PokerTableLayout.seatFrames(for: canvas)
            let operation = PokerTableLayout.betControlRegion(for: canvas)

            XCTAssertEqual(seatFrames.count, 9)
            for frame in seatFrames {
                XCTAssertTrue(safeCanvas.contains(frame))
                XCTAssertFalse(frame.intersects(operation))
            }

            for index in seatFrames.indices {
                let bet = PokerTableLayout.betPosition(forSeatAt: index, canvas: canvas)
                XCTAssertTrue(safeCanvas.contains(bet))
                XCTAssertFalse(operation.contains(bet))
                XCTAssertTrue(seatFrames.allSatisfy { !$0.contains(bet) })
            }
        }
    }

    func testPlayableTableExposesDepartureControl() throws {
        let source = try String(
            contentsOfFile: #filePath
                .replacingOccurrences(of: "RiverClubTests/PokerTableLayoutTests.swift", with: "RiverClub/Features/Table/PokerTableView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("table.leave"))
        XCTAssertTrue(source.contains("onRequestLeave"))
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let horizontal = x - other.x
        let vertical = y - other.y
        return (horizontal * horizontal + vertical * vertical).squareRoot()
    }
}
