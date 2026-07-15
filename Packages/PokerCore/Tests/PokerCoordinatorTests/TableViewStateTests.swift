import Foundation
import PokerCore
import Testing
@testable import PokerCoordinator

@Test func 面对下注时显示弃牌跟注和合法加注范围() throws {
    let legal = try decodeLegalActions(
        #"{"canFold":true,"canCheck":false,"callAmount":200,"minimumBet":null,"minimumRaiseTo":600,"maximumRaiseTo":2000,"canAllIn":true}"#
    )
    let controls = try TableActionControls(legalActions: legal)
    #expect(controls.canFold)
    #expect(controls.middle == .call(try Chips(200)))
    #expect(
        controls.aggressive == .raise(
            minimum: try Chips(600),
            maximum: try Chips(2_000),
            canAllIn: true
        )
    )
}

@Test func 安全状态编码只包含真人明牌和公开数据() throws {
    let data = try JSONEncoder().encode(makeSafeTableViewState())
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(!text.contains("deck"))
    #expect(!text.contains("seed"))
    #expect(!text.contains("checkpoint"))
    #expect(!text.contains("opponentHoleCards"))
}
