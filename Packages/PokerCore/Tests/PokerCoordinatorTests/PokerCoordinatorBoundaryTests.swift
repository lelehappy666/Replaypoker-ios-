import PokerCore
import PokerSession
import Testing
@testable import PokerCoordinator

@Test func 归零机器人补至目标筹码且真人余额不变() throws {
    let fixture = try CoordinatorStoreFixture.finishedHandWithBustedBot()
    let balance = fixture.store.accountBalance
    let target = try Chips(10_000)
    try fixture.store.refillBotSeat(fixture.bustedBot, to: target)
    #expect(fixture.store.cashSession?.seats.first { $0.id == fixture.bustedBot }?.stack == target)
    #expect(fixture.store.accountBalance == balance)
}

@Test func 安全摊牌观察排除已弃牌底牌() throws {
    let fixture = try CoordinatorStoreFixture.pendingShowdown()
    let showdown = try #require(fixture.store.pendingShowdownObservation)
    #expect(showdown.cardsBySeat[fixture.showdownSeat]?.count == 2)
    #expect(showdown.cardsBySeat[fixture.foldedSeat] == nil)
}

@Test func 河牌完成时存档保留已弃牌排名但安全观察不泄露底牌() throws {
    let fixture = try CoordinatorStoreFixture.pendingShowdown()
    #expect(fixture.completedRecord.handRanksBySeat[fixture.foldedSeat] != nil)
    #expect(fixture.completedRecord.holeCardsBySeat[fixture.foldedSeat]?.count == 2)
    #expect(fixture.store.pendingShowdownObservation?.cardsBySeat[fixture.foldedSeat] == nil)
}
