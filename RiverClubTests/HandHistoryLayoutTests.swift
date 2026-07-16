import CoreGraphics
import PokerCore
import PokerSession
import SwiftUI
import XCTest
@testable import RiverClub

final class HandHistoryLayoutTests: XCTestCase {
    func testHistoryEmptyCopyMatchesTheProductContract() {
        XCTAssertEqual(
            HandHistoryEmptyPresentation.noRecordsMessage,
            "完成一局后会在这里保存牌局记录"
        )
        XCTAssertEqual(
            HandHistoryEmptyPresentation.filteredMessage,
            "当前筛选条件下没有牌局"
        )
    }

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

    func testDeletionConfirmationCopyAndIdentifiersAreExplicit() throws {
        let detail = try HandHistoryPresentation.detail(
            from: makeHistoryRecord(
                archiveMetadata: try makePresentationArchiveMetadata()
            )
        )

        XCTAssertEqual(
            HandHistoryDeletionPresentation.singleMessage(for: detail),
            "\(detail.tableName) · \(detail.localDay.rawValue) · 第 \(detail.handNumber) 手"
        )
        XCTAssertEqual(
            HandHistoryDeletionPresentation.deleteAllMessage,
            "此操作只会删除牌局存档，余额、统计和账本不会删除。"
        )
        XCTAssertEqual(
            HandHistoryDeletionPresentation.confirmDeleteOneIdentifier,
            "history.confirmDeleteOne"
        )
        XCTAssertEqual(
            HandHistoryDeletionPresentation.confirmDeleteAllIdentifier,
            "history.confirmDeleteAll"
        )
        XCTAssertEqual(
            HandHistoryDeletionPresentation.cancelDeleteIdentifier,
            "history.cancelDelete"
        )
    }

    func testDeletionErrorKeepsTheSameOverlayAndConfirmationAction() throws {
        let record = try makeHistoryRecord(
            archiveMetadata: try makePresentationArchiveMetadata()
        )
        let detail = try HandHistoryPresentation.detail(from: record)
        let item = try HandHistoryPresentation.listItem(from: record)
        var state = HandHistoryViewState(
            loadState: .loaded([item]),
            selection: detail,
            pendingDeletion: .hand(record.id)
        )
        let before = try XCTUnwrap(
            HandHistoryDeletionPresentation.overlay(for: state)
        )

        state.deletionError = "牌局存档删除失败，请重试。"
        let retry = try XCTUnwrap(
            HandHistoryDeletionPresentation.overlay(for: state)
        )

        XCTAssertEqual(retry.pendingDeletion, before.pendingDeletion)
        XCTAssertEqual(
            retry.confirmationIdentifier,
            HandHistoryDeletionPresentation.confirmDeleteOneIdentifier
        )
        XCTAssertTrue(retry.message.contains("牌局存档删除失败，请重试。"))
    }

    func testSingleDeletionOverlayStaysVisibleWhenSelectionDisappears() throws {
        let record = try makeHistoryRecord(
            archiveMetadata: try makePresentationArchiveMetadata()
        )
        let item = try HandHistoryPresentation.listItem(from: record)
        let state = HandHistoryViewState(
            loadState: .loaded([item]),
            selection: nil,
            pendingDeletion: .hand(record.id)
        )

        let overlay = try XCTUnwrap(
            HandHistoryDeletionPresentation.overlay(for: state)
        )

        XCTAssertEqual(overlay.pendingDeletion, .hand(record.id))
        XCTAssertEqual(
            overlay.message,
            "\(item.tableName) · \(item.localDay.rawValue) · 第 \(item.handNumber) 手"
        )
    }

    func testPendingHandWithoutSelectionOrItemsStillHasVisibleOverlay() throws {
        let id = try HandID("temporarily-unavailable-hand")
        let state = HandHistoryViewState(
            loadState: .failed("牌局存档读取失败，请重试。"),
            pendingDeletion: .hand(id)
        )

        let overlay = try XCTUnwrap(
            HandHistoryDeletionPresentation.overlay(for: state)
        )

        XCTAssertEqual(overlay.pendingDeletion, .hand(id))
        XCTAssertEqual(
            overlay.confirmationIdentifier,
            HandHistoryDeletionPresentation.confirmDeleteOneIdentifier
        )
        XCTAssertFalse(overlay.message.isEmpty)
        XCTAssertEqual(overlay.escapeAction, .cancel)
    }

    func testDeletionModalUsesScrollableStackedLayoutForLargeTypeAt424Points() {
        let layout = HandHistoryDeletionLayout.metrics(
            canvasHeight: 424,
            dynamicTypeSize: .accessibility3
        )

        XCTAssertTrue(layout.usesVerticalScrolling)
        XCTAssertTrue(layout.stacksActionsVertically)
    }
}
