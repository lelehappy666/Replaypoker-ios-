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

@Test func 安全状态明确且唯一标记真人身份() throws {
    let state = try makeSafeTableViewState()
    let humans = state.seats.filter { $0.isHuman }

    #expect(humans.count == 1)
    #expect(humans[0].displayName == "玩家")
    #expect(
        state.seats.first(where: { !$0.isHuman })?.cards
            == [.faceDown, .faceDown]
    )
}

@Test func 旧座位资料缺少头像标识仍会解码为空() throws {
    let profile = try TableSeatProfile(
        id: try SeatID(0),
        displayName: "玩家",
        avatarAssetName: "avatar-player"
    )
    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))
            as? [String: Any]
    )
    object.removeValue(forKey: "avatarAssetName")

    let decoded = try JSONDecoder().decode(
        TableSeatProfile.self,
        from: JSONSerialization.data(withJSONObject: object)
    )

    #expect(decoded.avatarAssetName == nil)

    let state = TableSeatState(
        id: try SeatID(0),
        displayName: "玩家",
        avatarAssetName: "avatar-player",
        isHuman: true,
        stack: try Chips(800),
        committedThisStreet: try Chips(0),
        hasFolded: false,
        isAllIn: false,
        isDealer: false,
        isCurrentActor: true,
        cards: [.faceDown, .faceDown]
    )
    var stateObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
            as? [String: Any]
    )
    stateObject.removeValue(forKey: "avatarAssetName")

    let decodedState = try JSONDecoder().decode(
        TableSeatState.self,
        from: JSONSerialization.data(withJSONObject: stateObject)
    )

    #expect(decodedState.avatarAssetName == nil)
}
