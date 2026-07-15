import PokerCoordinator
import PokerCore
import XCTest
@testable import RiverClub

@MainActor
final class PokerTableInteractionTests: XCTestCase {
    func testFailedActionShowsMessageAndRestoresButtons() async throws {
        let model = TableActionRequestModel()

        await model.send(.fold) { _ in
            throw PokerCoordinatorError.illegalIntent
        }

        XCTAssertFalse(model.isSending)
        XCTAssertEqual(model.errorMessage, "操作失败，请重试。")
        XCTAssertEqual(model.retryIntent(for: .waitingForHuman), .fold)

        model.dismissError()
        XCTAssertNil(model.errorMessage)
    }

    func testRetryUsesOnlyIntentValidForCurrentPhase() async throws {
        let model = TableActionRequestModel()
        await model.send(.fold) { _ in throw PokerCoordinatorError.illegalIntent }

        XCTAssertNil(model.retryIntent(for: .botThinking))
        XCTAssertEqual(model.retryIntent(for: .waitingForHuman), .fold)
        XCTAssertEqual(model.retryIntent(for: .saveFailed), .retrySave)
        XCTAssertEqual(model.retryIntent(for: .awaitingNextHand), .nextHand)
    }

    func testConsecutiveAnimationEventsReturnToBaseline() throws {
        let seat = try SeatID(1)
        var presentation = TableAnimationPresentation()

        presentation.begin(
            .dealHoleCard(seat: seat, card: .faceDown),
            token: 1
        )
        presentation.advance(token: 1)
        presentation.begin(
            .moveCommitmentToPot(seat: seat, amount: try Chips(200)),
            token: 2
        )
        presentation.advance(token: 2)
        presentation.reset(token: 2)

        XCTAssertEqual(presentation.holeCardScale(for: seat), 1)
        XCTAssertEqual(presentation.chipOffset, 0)
        XCTAssertNil(presentation.event)
    }

    func testWinnerEventProducesHighlightBeforeReturningToBaseline() throws {
        let winner = try SeatID(3)
        var presentation = TableAnimationPresentation()

        presentation.begin(.highlightWinner(winner), token: 7)
        presentation.advance(token: 7)

        XCTAssertGreaterThan(presentation.winnerScale(for: winner), 1)
        XCTAssertTrue(presentation.isWinnerHighlighted(winner))

        presentation.reset(token: 7)
        XCTAssertEqual(presentation.winnerScale(for: winner), 1)
        XCTAssertFalse(presentation.isWinnerHighlighted(winner))
    }
}
