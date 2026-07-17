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
                guard let betFrame = PokerTableLayout.betFrame(forSeatAt: index, canvas: canvas) else {
                    return XCTFail("支持的画布必须为座位 \(index) 提供安全下注框")
                }
                let position = CGPoint(x: betFrame.midX, y: betFrame.midY)
                let seatCenter = CGPoint(x: seatFrames[index].midX, y: seatFrames[index].midY)
                let centerVector = CGPoint(x: center.x - seatCenter.x, y: center.y - seatCenter.y)
                let betVector = CGPoint(x: position.x - seatCenter.x, y: position.y - seatCenter.y)
                let progress = (centerVector.x * betVector.x + centerVector.y * betVector.y)
                    / (centerVector.x * centerVector.x + centerVector.y * centerVector.y)

                XCTAssertLessThan(position.distance(to: center), seatCenter.distance(to: center))
                XCTAssertGreaterThan(progress, 0)
                XCTAssertLessThan(progress, 1)
                XCTAssertEqual(
                    betFrame.size.width,
                    PokerTableLayout.betStackBaseSize.width * PokerTableLayout.betScale(for: canvas),
                    accuracy: 0.001
                )
                XCTAssertEqual(
                    betFrame.size.height,
                    PokerTableLayout.betStackBaseSize.height * PokerTableLayout.betScale(for: canvas),
                    accuracy: 0.001
                )
                XCTAssertTrue(PokerTableLayout.safeCanvas(for: canvas).contains(betFrame))
                XCTAssertTrue(seatFrames.allSatisfy { !$0.intersects(betFrame) })
                XCTAssertTrue(slots.allSatisfy { !$0.intersects(betFrame) })
                XCTAssertFalse(operation.intersects(betFrame))
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
                guard let bet = PokerTableLayout.betFrame(forSeatAt: index, canvas: canvas) else {
                    return XCTFail("支持的画布必须为座位 \(index) 提供安全下注框")
                }
                XCTAssertTrue(safeCanvas.contains(bet))
                XCTAssertFalse(operation.intersects(bet))
                XCTAssertTrue(seatFrames.allSatisfy { !$0.intersects(bet) })
            }

            XCTAssertNil(PokerTableLayout.betFrame(forSeatAt: -1, canvas: canvas))
            XCTAssertNil(PokerTableLayout.betFrame(forSeatAt: seatFrames.count, canvas: canvas))
        }
    }

    func testCenterBoardKeepsHandPotAndCommunitySlotsSeparate() {
        for canvas in canvases {
            let safeCanvas = PokerTableLayout.safeCanvas(for: canvas)
            let board = PokerTableLayout.centerBoardRegion(for: canvas)
            let slots = PokerTableLayout.communityCardFrames(for: canvas)
            let hand = PokerTableLayout.currentHandFrame(for: canvas)
            let pot = PokerTableLayout.potFrame(for: canvas)
            let seats = PokerTableLayout.seatFrames(for: canvas)
            let action = PokerTableLayout.betControlRegion(for: canvas)

            XCTAssertTrue(board.contains(hand))
            XCTAssertTrue(board.contains(pot))
            XCTAssertTrue(safeCanvas.contains(hand))
            XCTAssertTrue(safeCanvas.contains(pot))
            XCTAssertFalse(hand.intersects(pot))
            XCTAssertFalse(action.intersects(pot))
            XCTAssertTrue(seats.allSatisfy { !$0.intersects(pot) })
            for slot in slots {
                XCTAssertFalse(hand.intersects(slot))
                XCTAssertFalse(pot.intersects(slot))
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
