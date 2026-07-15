import PokerCoordinator
import PokerCore
import XCTest
@testable import RiverClub

final class BetControlBarTests: XCTestCase {
    func testRaisePresentationTurnsMaximumIntoAllIn() throws {
        let aggressive = TableAggressiveAction.raise(
            minimum: try Chips(600),
            maximum: try Chips(2_000),
            canAllIn: true
        )

        XCTAssertEqual(
            BetControlPresentation.title(
                for: aggressive,
                amount: try Chips(2_000)
            ),
            "全下"
        )
        XCTAssertEqual(
            BetControlPresentation.title(
                for: aggressive,
                amount: try Chips(1_000)
            ),
            "加注 1,000"
        )
    }

    func testBetAndMiddleActionTitlesComeOnlyFromControls() throws {
        XCTAssertEqual(
            BetControlPresentation.title(for: TableMiddleAction.check),
            "过牌"
        )
        XCTAssertEqual(
            BetControlPresentation.title(
                for: .call(try Chips(400))
            ),
            "跟注 400"
        )
        XCTAssertEqual(
            BetControlPresentation.title(
                for: .bet(
                    minimum: try Chips(400),
                    maximum: try Chips(2_000),
                    canAllIn: false
                ),
                amount: try Chips(900)
            ),
            "下注 900"
        )
    }

    func testAggressiveRangeUsesLegalMinimumAndMaximum() throws {
        let aggressive = TableAggressiveAction.raise(
            minimum: try Chips(600),
            maximum: try Chips(2_000),
            canAllIn: false
        )

        XCTAssertEqual(
            BetControlPresentation.range(for: aggressive),
            600...2_000
        )
    }

    func testPreviousSliderAmountIsClippedWhenControlsChange() throws {
        let aggressive = TableAggressiveAction.raise(
            minimum: try Chips(600),
            maximum: try Chips(2_000),
            canAllIn: false
        )

        XCTAssertEqual(
            BetControlPresentation.clampedAmount(2_500, for: aggressive),
            2_000
        )
        XCTAssertEqual(
            BetControlPresentation.clampedAmount(200, for: aggressive),
            600
        )
    }

    func testPresetAmountsAreClippedDeduplicatedAndExcludeMinimum() throws {
        let aggressive = TableAggressiveAction.raise(
            minimum: try Chips(600),
            maximum: try Chips(900),
            canAllIn: false
        )

        XCTAssertEqual(
            BetControlPresentation.presets(
                for: aggressive,
                pot: try Chips(2_000)
            ),
            [BetControlPreset(title: "半池", amount: 900)]
        )

        let minimumOnly = TableAggressiveAction.bet(
            minimum: try Chips(800),
            maximum: try Chips(2_000),
            canAllIn: false
        )
        XCTAssertEqual(
            BetControlPresentation.presets(
                for: minimumOnly,
                pot: try Chips(800)
            ),
            []
        )
    }

    func testPhasePresentationUsesCoordinatorPhase() {
        XCTAssertEqual(PokerTablePresentation.status(for: .dealing), "发牌中")
        XCTAssertEqual(PokerTablePresentation.status(for: .botThinking), "思考中")
        XCTAssertEqual(PokerTablePresentation.status(for: .awaitingNextHand), "本手牌已结束")
        XCTAssertEqual(PokerTablePresentation.status(for: .savingResult), "正在保存结果")
        XCTAssertEqual(PokerTablePresentation.status(for: .suspended), "牌局已暂停")
    }
}
