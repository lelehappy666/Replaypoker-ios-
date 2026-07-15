import Foundation
import PokerCore
import Testing
@testable import PokerCoordinator

@Test func 翻牌事件逐张映射且行动动画先于下一行动() throws {
    let cards = try decodeCards(
        #"[{"rank":14,"suit":3},{"rank":13,"suit":2},{"rank":7,"suit":1}]"#
    )
    let seat = try SeatID(2)
    let events = try CashTableAnimationMapper.map(
        [
            .actionApplied(seat: seat, action: .check),
            .streetChanged(.flop),
            .communityCardsDealt(cards),
        ],
        humanSeat: try SeatID(0),
        humanCards: [],
        beforeAction: CashTableAnimationSnapshot(
            commitments: [seat: try Chips(100)],
            stacks: [seat: try Chips(3_900)],
            currentBet: try Chips(100)
        )
    )

    #expect(events.map(\.kind) == [
        .showAction, .streetChanged, .revealCommunityCard,
        .revealCommunityCard, .revealCommunityCard,
    ])
}

@Test func 行动先展示再按投入差值移动筹码() throws {
    let seat = try SeatID(2)
    let events = try CashTableAnimationMapper.map(
        [.actionApplied(seat: seat, action: .call)],
        humanSeat: try SeatID(0),
        humanCards: [],
        beforeAction: CashTableAnimationSnapshot(
            commitments: [seat: try Chips(100)],
            stacks: [seat: try Chips(3_900)],
            currentBet: try Chips(350)
        )
    )

    #expect(events == [
        .showAction(seat: seat, action: .call),
        .moveCommitmentToPot(seat: seat, amount: try Chips(250)),
    ])
}

@Test func 投入差值为负数时拒绝映射() throws {
    let seat = try SeatID(2)
    #expect(throws: PokerCoordinatorError.chipArithmeticOverflow) {
        try CashTableAnimationMapper.map(
            [.actionApplied(seat: seat, action: .call)],
            humanSeat: try SeatID(0),
            humanCards: [],
            beforeAction: CashTableAnimationSnapshot(
                commitments: [seat: try Chips(350)],
                stacks: [seat: try Chips(3_650)],
                currentBet: try Chips(100)
            )
        )
    }
}

@Test func 真人底牌按发牌顺序明牌且机器人始终牌背() throws {
    let human = try SeatID(0)
    let bot = try SeatID(1)
    let cards = try decodeCards(
        #"[{"rank":14,"suit":3},{"rank":13,"suit":2}]"#
    )
    let events = try CashTableAnimationMapper.map(
        [
            .holeCardsDealt(seat: bot),
            .holeCardsDealt(seat: human),
            .holeCardsDealt(seat: bot),
            .holeCardsDealt(seat: human),
        ],
        humanSeat: human,
        humanCards: cards.map(TableCardState.faceUp),
        beforeAction: nil
    )

    #expect(events == [
        .dealHoleCard(seat: bot, card: .faceDown),
        .dealHoleCard(seat: human, card: .faceUp(cards[0])),
        .dealHoleCard(seat: bot, card: .faceDown),
        .dealHoleCard(seat: human, card: .faceUp(cards[1])),
    ])
}

@Test func 真人底牌不是两张时拒绝映射() throws {
    #expect(throws: PokerCoordinatorError.missingObservation) {
        try CashTableAnimationMapper.map(
            [.holeCardsDealt(seat: try SeatID(0))],
            humanSeat: try SeatID(0),
            humanCards: [.faceDown],
            beforeAction: nil
        )
    }
}

@Test func 底池分配按座位排序且逐个高亮赢家() throws {
    let low = try SeatID(1)
    let high = try SeatID(7)
    let events = try CashTableAnimationMapper.map(
        [.potAwarded(
            potIndex: 2,
            winners: [high, low],
            amounts: [high: try Chips(300), low: try Chips(301)]
        )],
        humanSeat: try SeatID(0),
        humanCards: [],
        beforeAction: nil
    )

    #expect(events == [
        .awardPot(seat: low, amount: try Chips(301), potIndex: 2),
        .highlightWinner(low),
        .awardPot(seat: high, amount: try Chips(300), potIndex: 2),
        .highlightWinner(high),
    ])
}

@Test func 换街过牌不移动筹码且继续映射牌面() throws {
    let seat = try SeatID(0)
    let cards = try decodeCards(
        #"[{"rank":14,"suit":3},{"rank":13,"suit":2},{"rank":7,"suit":1}]"#
    )
    let mapped = try CashTableAnimationMapper.map(
        [
            .actionApplied(seat: seat, action: .check),
            .streetChanged(.flop),
            .communityCardsDealt(cards),
        ],
        humanSeat: seat,
        humanCards: [],
        beforeAction: CashTableAnimationSnapshot(
            commitments: [seat: try Chips(100)],
            stacks: [seat: try Chips(3_900)],
            currentBet: try Chips(100)
        )
    )
    #expect(mapped.map(\.kind) == [
        .showAction, .streetChanged, .revealCommunityCard,
        .revealCommunityCard, .revealCommunityCard,
    ])
}

@Test func 跟注加注和全下使用转换前安全快照计算贡献() throws {
    let seat = try SeatID(4)
    let base = CashTableAnimationSnapshot(
        commitments: [seat: try Chips(100)],
        stacks: [seat: try Chips(900)],
        currentBet: try Chips(300)
    )
    let call = try CashTableAnimationMapper.map(
        [.actionApplied(seat: seat, action: .call), .streetChanged(.flop)],
        humanSeat: try SeatID(0), humanCards: [], beforeAction: base
    )
    let raise = try CashTableAnimationMapper.map(
        [.actionApplied(seat: seat, action: .raiseTo(try Chips(600))), .handCompleted],
        humanSeat: try SeatID(0), humanCards: [], beforeAction: base
    )
    let allIn = try CashTableAnimationMapper.map(
        [.actionApplied(seat: seat, action: .allIn), .handCompleted],
        humanSeat: try SeatID(0), humanCards: [], beforeAction: base
    )

    #expect(call == [
        .showAction(seat: seat, action: .call),
        .moveCommitmentToPot(seat: seat, amount: try Chips(200)),
        .streetChanged(.flop),
    ])
    #expect(raise == [
        .showAction(seat: seat, action: .raiseTo(try Chips(600))),
        .moveCommitmentToPot(seat: seat, amount: try Chips(500)),
    ])
    #expect(allIn == [
        .showAction(seat: seat, action: .allIn),
        .moveCommitmentToPot(seat: seat, amount: try Chips(900)),
    ])
}
