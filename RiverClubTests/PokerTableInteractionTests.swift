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
        XCTAssertNil(model.retryIntent(for: .awaitingNextHand))
    }

    func testOrdinaryFailureRetriesOriginalIntent() async throws {
        let model = TableActionRequestModel()
        await model.send(.fold) { _ in throw PokerCoordinatorError.illegalIntent }
        var sent: [TableIntent] = []

        await model.retry(
            for: .waitingForHuman,
            send: { intent in sent.append(intent) },
            resume: { XCTFail("普通非法意图不应恢复牌局") }
        )

        XCTAssertEqual(sent, [.fold])
        XCTAssertNil(model.errorMessage)
    }

    func testSuspendedRetryFailureKeepsIntentAndShowsRecoveryMessage() async throws {
        let model = TableActionRequestModel()
        await model.send(.nextHand) { _ in throw PokerCoordinatorError.suspended }

        await model.retry(
            for: .suspended,
            send: { _ in XCTFail("暂停阶段不应重发下一手") },
            resume: { throw PokerCoordinatorError.suspended }
        )

        XCTAssertEqual(model.errorMessage, "恢复牌局失败，请重试。")
        XCTAssertTrue(model.canRetry(for: .suspended))
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

    func testSameAnimationWithDifferentSequencesIsConsumedTwice() throws {
        let seat = try SeatID(1)
        let event = TableAnimationEvent.dealHoleCard(seat: seat, card: .faceDown)
        var presentation = TableAnimationPresentation()

        presentation.begin(event, token: 1)
        presentation.begin(event, token: 2)

        XCTAssertEqual(presentation.activeToken, 2)
        XCTAssertEqual(presentation.event, event)
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

    func testAwardPotMovesChipsTowardWinnerAndKeepsAmount() throws {
        let winner = try SeatID(3)
        let amount = try Chips(3_600)
        var presentation = TableAnimationPresentation()

        presentation.begin(
            .awardPot(seat: winner, amount: amount),
            token: 9
        )
        presentation.advance(token: 9)

        XCTAssertEqual(presentation.awardTargetSeat, winner)
        XCTAssertEqual(presentation.awardAmount, amount)
        XCTAssertEqual(presentation.awardProgress, 1)

        presentation.reset(token: 9)
        XCTAssertNil(presentation.awardTargetSeat)
        XCTAssertNil(presentation.awardAmount)
        XCTAssertEqual(presentation.awardProgress, 0)
    }

    func testChipFlightClustersKeepStaggeredProgressWithReducedMotion() throws {
        let seat = try SeatID(3)
        var presentation = TableAnimationPresentation()
        presentation.begin(
            .moveCommitmentToPot(seat: seat, amount: try Chips(600)),
            token: 12
        )
        presentation.advance(token: 12, progress: 0.55)

        let normal = (0..<4).map {
            presentation.chipFlightProgress(at: $0, reduceMotion: false)
        }
        let reduced = (0..<4).map {
            presentation.chipFlightProgress(at: $0, reduceMotion: true)
        }

        XCTAssertGreaterThan(normal[0], normal[3])
        XCTAssertGreaterThan(reduced[0], reduced[3])
        XCTAssertGreaterThan(reduced[3], 0)
        XCTAssertEqual(presentation.chipFlightSeat, seat)
        XCTAssertEqual(presentation.chipFlightAmount, try Chips(600))
    }

    func testChipFlightDisplayAmountsConserveChipsDuringBetAndAward() throws {
        let seat = try SeatID(2)
        var presentation = TableAnimationPresentation()

        presentation.begin(
            .postBlind(seat: seat, amount: try Chips(600)),
            token: 21
        )
        presentation.advance(token: 21, progress: 0.5)

        let stack = presentation.displayedStack(
            finalAmount: 9_400,
            seat: seat,
            reduceMotion: false
        )
        let commitment = presentation.displayedCommitment(
            finalAmount: 600,
            seat: seat,
            reduceMotion: false
        )
        XCTAssertEqual(stack + commitment, 10_000)
        XCTAssertGreaterThan(stack, 9_400)
        XCTAssertLessThan(commitment, 600)

        presentation.begin(
            .awardPot(seat: seat, amount: try Chips(2_400)),
            token: 22
        )
        presentation.advance(token: 22, progress: 0.5)

        let winnerStack = presentation.displayedStack(
            finalAmount: 12_400,
            seat: seat,
            reduceMotion: false
        )
        let pot = presentation.displayedPot(
            finalAmount: 0,
            reduceMotion: false
        )
        XCTAssertEqual(winnerStack + pot, 12_400)
        XCTAssertLessThan(winnerStack, 12_400)
        XCTAssertGreaterThan(pot, 0)
    }

    func testOlderAwardResetDoesNotClearNewerWinnerAnnouncement() throws {
        let winner = try SeatID(3)
        var presentation = TableAnimationPresentation()

        presentation.begin(
            .awardPot(seat: winner, amount: try Chips(3_600)),
            token: 9
        )
        presentation.advance(token: 9)
        presentation.begin(.highlightWinner(winner), token: 10)
        presentation.advance(token: 10)
        presentation.reset(token: 9)

        XCTAssertEqual(presentation.event, .highlightWinner(winner))
        XCTAssertTrue(presentation.isWinnerHighlighted(winner))
    }

    func testCancelledActionDoesNotPublishFailureAndRestoresSendingState() async throws {
        let model = TableActionRequestModel()
        let task = Task { @MainActor in
            await model.send(.fold) { _ in
                try await Task.sleep(for: .seconds(60))
            }
        }
        await Task.yield()

        task.cancel()
        await task.value

        XCTAssertFalse(model.isSending)
        XCTAssertNil(model.errorMessage)
    }
}
