import PokerCore
import XCTest
@testable import RiverClub

@MainActor
final class TableSocialInteractionTests: XCTestCase {
    func testSendingMessageShowsHumanBubbleAndAtMostOneBotReply() async throws {
        let human = try SeatID(8)
        let bots = [try SeatID(1), try SeatID(2)]
        let model = TableSocialInteractionModel(
            now: { 10 },
            randomUnit: { 0 },
            responseDelay: .zero,
            bubbleDuration: .seconds(30)
        )

        let accepted = await model.send(
            .message(.niceHand),
            humanSeat: human,
            eligibleBots: bots
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(model.visibleBubbles.filter(\.isHuman).count, 1)
        XCTAssertEqual(model.visibleBubbles.filter { !$0.isHuman }.count, 1)
        XCTAssertTrue(model.visibleBubbles.allSatisfy { $0.seat == human || bots.contains($0.seat) })
    }

    func testCooldownRejectsRepeatedHumanMessage() async throws {
        var currentTime: TimeInterval = 20
        let human = try SeatID(8)
        let model = TableSocialInteractionModel(
            now: { currentTime },
            randomUnit: { 1 },
            responseDelay: .zero,
            bubbleDuration: .seconds(30),
            cooldown: 2
        )

        let firstAccepted = await model.send(
            .reaction(.smile), humanSeat: human, eligibleBots: []
        )
        XCTAssertTrue(firstAccepted)
        currentTime = 21
        let secondAccepted = await model.send(
            .reaction(.applause), humanSeat: human, eligibleBots: []
        )
        XCTAssertFalse(secondAccepted)
        currentTime = 22.1
        let thirdAccepted = await model.send(
            .reaction(.applause), humanSeat: human, eligibleBots: []
        )
        XCTAssertTrue(thirdAccepted)
    }

    func testBubbleAutomaticallyDisappears() async throws {
        let human = try SeatID(8)
        let model = TableSocialInteractionModel(
            now: { 10 },
            randomUnit: { 1 },
            responseDelay: .zero,
            bubbleDuration: .milliseconds(10),
            cooldown: 0
        )

        _ = await model.send(.message(.hello), humanSeat: human, eligibleBots: [])
        XCTAssertEqual(model.visibleBubbles.count, 1)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(model.visibleBubbles.isEmpty)
    }
}
