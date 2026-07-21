import PokerCoordinator
import PokerCore
import XCTest
@testable import RiverClub

final class TableSoundServiceTests: XCTestCase {
    func testAnimationEventsMapToExpectedSoundCues() throws {
        let seat = try SeatID(1)
        let card = try XCTUnwrap(Card.fullDeck.first)

        XCTAssertEqual(
            TableSoundCue.cue(for: .dealHoleCard(seat: seat, card: .faceDown)),
            .deal
        )
        XCTAssertEqual(
            TableSoundCue.cue(for: .revealCommunityCard(card: card, index: 0)),
            .deal
        )
        XCTAssertEqual(
            TableSoundCue.cue(for: .postBlind(seat: seat, amount: try Chips(100))),
            .chips
        )
        XCTAssertEqual(
            TableSoundCue.cue(for: .awardPot(seat: seat, amount: try Chips(500))),
            .win
        )
        XCTAssertNil(TableSoundCue.cue(for: .highlightWinner(seat)))
        XCTAssertTrue(TableSoundPreference.defaultEnabled)
        XCTAssertFalse(TableSoundPreference.storageKey.isEmpty)
    }
}
