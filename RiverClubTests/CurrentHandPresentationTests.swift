import PokerCore
import XCTest
@testable import RiverClub

final class CurrentHandPresentationTests: XCTestCase {
    func testPreflopDescribesPairSuitedAndOffsuit() {
        XCTAssertEqual(
            CurrentHandPresentation.text(
                holeCards: [
                    card(.ace, .spades),
                    card(.ace, .hearts),
                ],
                communityCards: []
            ),
            "起手牌：AA 对子"
        )
        XCTAssertEqual(
            CurrentHandPresentation.text(
                holeCards: [
                    card(.king, .hearts),
                    card(.seven, .hearts),
                ],
                communityCards: []
            ),
            "起手牌：K7 同花"
        )
        XCTAssertEqual(
            CurrentHandPresentation.text(
                holeCards: [
                    card(.king, .diamonds),
                    card(.seven, .hearts),
                ],
                communityCards: []
            ),
            "起手牌：K7 不同花"
        )
    }

    func testBoardProducesBestFiveCardChineseRank() {
        XCTAssertEqual(
            CurrentHandPresentation.text(
                holeCards: [
                    card(.king, .diamonds),
                    card(.seven, .spades),
                ],
                communityCards: [
                    card(.king, .hearts),
                    card(.ten, .hearts),
                    card(.nine, .clubs),
                    card(.nine, .hearts),
                    card(.two, .hearts),
                ]
            ),
            "当前牌型：两对，K 和 9"
        )
    }

    func testBestFiveCardsPreferFlushOverVisibleTwoPair() {
        XCTAssertEqual(
            CurrentHandPresentation.text(
                holeCards: [
                    card(.king, .diamonds),
                    card(.seven, .hearts),
                ],
                communityCards: [
                    card(.king, .hearts),
                    card(.ten, .hearts),
                    card(.nine, .clubs),
                    card(.nine, .hearts),
                    card(.two, .hearts),
                ]
            ),
            "当前牌型：同花，K 高"
        )
    }

    func testStraightFlushAndFullHouseUseChineseHighCardText() {
        XCTAssertEqual(
            CurrentHandPresentation.text(
                holeCards: [
                    card(.ace, .hearts),
                    card(.king, .hearts),
                ],
                communityCards: [
                    card(.queen, .hearts),
                    card(.jack, .hearts),
                    card(.ten, .hearts),
                ]
            ),
            "当前牌型：同花顺，A 高"
        )
        XCTAssertEqual(
            CurrentHandPresentation.text(
                holeCards: [
                    card(.queen, .hearts),
                    card(.queen, .clubs),
                ],
                communityCards: [
                    card(.queen, .spades),
                    card(.six, .diamonds),
                    card(.six, .clubs),
                ]
            ),
            "当前牌型：葫芦，Q 带 6"
        )
    }

    func testMissingHumanHoleCardsDoesNotInventAHand() {
        XCTAssertNil(
            CurrentHandPresentation.text(
                holeCards: [card(.ace, .spades)],
                communityCards: []
            )
        )
    }

    private func card(_ rank: Rank, _ suit: Suit) -> Card {
        Card.fullDeck.first {
            $0.rank == rank && $0.suit == suit
        }!
    }
}
