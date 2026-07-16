import CoreGraphics
import SwiftUI
import XCTest
@testable import RiverClub

final class HandHistoryLayoutTests: XCTestCase {
    func testLandscapeHistoryKeepsFiltersAndRowsInsideSafeCanvas() {
        let layout = HandHistoryLayout.safeCanvas(width: 932, height: 424)

        XCTAssertEqual(layout.filterWidth, 220)
        XCTAssertGreaterThanOrEqual(layout.contentWidth, 640)
        XCTAssertGreaterThanOrEqual(layout.minimumRowHeight, 88)
    }

    func testDetailUsesNineUniqueSeatSlotsWithoutCardCompression() {
        let canvas = CGSize(width: 932 - 220, height: 424)
        let layout = HandHistoryDetailLayout.metrics(in: canvas)
        let slots = layout.seatSlots

        XCTAssertEqual(slots.count, 9)
        XCTAssertEqual(Set(slots.map(\.id)).count, 9)
        XCTAssertTrue(slots.allSatisfy { $0.cardSize.width >= 28 })
        XCTAssertTrue(slots.allSatisfy { $0.cardSize.height >= 40 })
        XCTAssertTrue(slots.allSatisfy { slot in
            slot.frame.minX >= layout.contentPadding
                && slot.frame.maxX <= canvas.width - layout.contentPadding
                && slot.frame.minY >= 0
                && slot.frame.maxY <= canvas.height
        })
    }

    func testLargeTypeFilterPanelUsesVerticalScrollingOnLandscapeCanvas() {
        let layout = HandHistoryFilterPanelLayout.metrics(
            canvasHeight: 424 - 40,
            dynamicTypeSize: .accessibility3
        )

        XCTAssertTrue(layout.usesVerticalScrolling)
        XCTAssertGreaterThan(layout.minimumContentHeight, layout.canvasHeight)
        XCTAssertGreaterThanOrEqual(layout.minimumControlHeight, 60)
    }

    func testHistoryRowsFitTheCanvasRemainingAfterTheAppSidebar() {
        let routedCanvas = HandHistoryLayout.safeCanvas(
            width: 932 - 220,
            height: 424
        )
        let row = HandHistoryLayout.rowMetrics(
            contentWidth: routedCanvas.contentWidth
        )

        XCTAssertLessThanOrEqual(row.minimumWidth, routedCanvas.contentWidth)
        XCTAssertGreaterThanOrEqual(row.cardSize.width, 28)
        XCTAssertGreaterThanOrEqual(row.cardSize.height, 40)
    }
}
