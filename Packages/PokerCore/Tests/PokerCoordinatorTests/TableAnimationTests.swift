import Foundation
import PokerSession
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
        ),
        dealer: try SeatID(0)
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
        ),
        dealer: try SeatID(0)
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
            ),
            dealer: try SeatID(0)
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
        beforeAction: nil,
        dealer: try SeatID(0)
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
            beforeAction: nil,
            dealer: try SeatID(0)
        )
    }
}

@Test func 底池分配按庄家后顺时针排序且逐个高亮赢家() throws {
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
        beforeAction: nil,
        dealer: try SeatID(0)
    )

    #expect(events == [
        .awardPot(seat: low, amount: try Chips(301)),
        .highlightWinner(low),
        .awardPot(seat: high, amount: try Chips(300)),
        .highlightWinner(high),
    ])
}

@Test func 同一赢家多个底池只产生一次派彩() throws {
    let winner = try SeatID(4)
    let events = try CashTableAnimationMapper.map(
        [
            .potAwarded(
                potIndex: 0,
                winners: [winner],
                amounts: [winner: try Chips(600)]
            ),
            .potAwarded(
                potIndex: 1,
                winners: [winner],
                amounts: [winner: try Chips(200)]
            ),
        ],
        humanSeat: try SeatID(0),
        humanCards: [],
        beforeAction: nil,
        dealer: try SeatID(1)
    )

    #expect(events == [
        .awardPot(seat: winner, amount: try Chips(800)),
        .highlightWinner(winner),
    ])
}

@Test func 多赢家跨边池按庄家后顺时针各派彩一次且总额守恒() throws {
    let dealer = try SeatID(7)
    let first = try SeatID(8)
    let second = try SeatID(2)
    let mapped = try CashTableAnimationMapper.map(
        [
            .potAwarded(
                potIndex: 0,
                winners: [second, first],
                amounts: [first: try Chips(600), second: try Chips(100)]
            ),
            .potAwarded(
                potIndex: 1,
                winners: [first],
                amounts: [first: try Chips(50)]
            ),
        ],
        humanSeat: try SeatID(0),
        humanCards: [],
        beforeAction: nil,
        dealer: dealer
    )

    #expect(mapped == [
        .awardPot(seat: first, amount: try Chips(650)),
        .highlightWinner(first),
        .awardPot(seat: second, amount: try Chips(100)),
        .highlightWinner(second),
    ])
    let awardTotal = mapped.reduce(into: 0) { total, event in
        if case let .awardPot(_, amount) = event {
            total += amount.rawValue
        }
    }
    #expect(awardTotal == 750)
}

@Test func 空结算不产生事件且零金额仍按赢家消费一次() throws {
    let dealer = try SeatID(1)
    let winner = try SeatID(3)
    let empty = try CashTableAnimationMapper.map(
        [],
        humanSeat: try SeatID(0),
        humanCards: [],
        beforeAction: nil,
        dealer: dealer
    )
    let zero = try CashTableAnimationMapper.map(
        [.potAwarded(
            potIndex: 0,
            winners: [winner],
            amounts: [winner: try Chips(0)]
        )],
        humanSeat: try SeatID(0),
        humanCards: [],
        beforeAction: nil,
        dealer: dealer
    )

    #expect(empty.isEmpty)
    #expect(zero == [
        .awardPot(seat: winner, amount: try Chips(0)),
        .highlightWinner(winner),
    ])
}

@Test func 聚合派彩保留未跟注归还在前的结算顺序() throws {
    let returned = try SeatID(1)
    let winner = try SeatID(4)
    let mapped = try CashTableAnimationMapper.map(
        [
            .uncalledBetReturned(seat: returned, amount: try Chips(50)),
            .potAwarded(
                potIndex: 0,
                winners: [winner],
                amounts: [winner: try Chips(600)]
            ),
            .potAwarded(
                potIndex: 1,
                winners: [winner],
                amounts: [winner: try Chips(200)]
            ),
        ],
        humanSeat: try SeatID(0),
        humanCards: [],
        beforeAction: nil,
        dealer: try SeatID(1)
    )

    #expect(mapped == [
        .returnUncalledBet(seat: returned, amount: try Chips(50)),
        .awardPot(seat: winner, amount: try Chips(800)),
        .highlightWinner(winner),
    ])
}

@Test func 聚合派彩溢出时拒绝映射() throws {
    let winner = try SeatID(4)
    #expect(throws: PokerCoordinatorError.chipArithmeticOverflow) {
        try CashTableAnimationMapper.map(
            [
                .potAwarded(
                    potIndex: 0,
                    winners: [winner],
                    amounts: [winner: try Chips(Int.max)]
                ),
                .potAwarded(
                    potIndex: 1,
                    winners: [winner],
                    amounts: [winner: try Chips(1)]
                ),
            ],
            humanSeat: try SeatID(0),
            humanCards: [],
            beforeAction: nil,
            dealer: try SeatID(1)
        )
    }
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
        ),
        dealer: try SeatID(0)
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
        humanSeat: try SeatID(0), humanCards: [], beforeAction: base,
        dealer: try SeatID(0)
    )
    let raise = try CashTableAnimationMapper.map(
        [.actionApplied(seat: seat, action: .raiseTo(try Chips(600))), .handCompleted],
        humanSeat: try SeatID(0), humanCards: [], beforeAction: base,
        dealer: try SeatID(0)
    )
    let allIn = try CashTableAnimationMapper.map(
        [.actionApplied(seat: seat, action: .allIn), .handCompleted],
        humanSeat: try SeatID(0), humanCards: [], beforeAction: base,
        dealer: try SeatID(0)
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

@Test @MainActor func 播放器记录正常节奏且减少动态时全部为零() async throws {
    let normalRecorder = AnimationSleepRecorder()
    let normal = try await CoordinatorScenario.automaticSettlement(
        repository: FailOnceSessionRepository(failSettlementOnce: false),
        animationRecorder: normalRecorder,
        reduceMotion: false
    )

    let opening = await normalRecorder.animationDurations()
    #expect(opening.filter { $0 == .milliseconds(80) }.count == 18)
    try await normal.playDeterministicallyToSettlement()
    await normal.waitForAutomaticSettlement()
    let allDurations = await normalRecorder.animationDurations()
    #expect(allDurations.filter { $0 == .milliseconds(180) }.count == 3)
    #expect(allDurations.filter { $0 == .milliseconds(220) }.count == 2)
    #expect(allDurations.contains(.milliseconds(250)))
    #expect(allDurations.contains(.milliseconds(650)))

    let reducedRecorder = AnimationSleepRecorder()
    _ = try await CoordinatorScenario.automaticSettlement(
        repository: FailOnceSessionRepository(failSettlementOnce: false),
        animationRecorder: reducedRecorder,
        reduceMotion: true
    )
    let reducedOpening = await reducedRecorder.animationDurations()
    #expect(reducedOpening.count == opening.count)
    #expect(reducedOpening.allSatisfy { $0 == .zero })
}

@Test @MainActor func 发牌每个序号只公布已发的牌且隐藏操作区() async throws {
    let recorder = AnimationPublicationRecorder()
    let scenario = try CoordinatorScenario.readyToStartWithHumanFirst(
        publicationRecorder: recorder
    )
    recorder.coordinator = scenario.coordinator

    try await scenario.coordinator.startHand(settings: .recommended)

    let dealing = recorder.states.filter { $0.animation?.kind == .dealHoleCard }
    #expect(dealing.count == 18)
    for (offset, state) in dealing.enumerated() {
        #expect(state.phase == .dealing)
        #expect(state.controls == nil)
        #expect(state.communityCards.isEmpty)
        #expect(state.seats.flatMap(\.cards).count == offset + 1)
        #expect(state.seats.filter { !$0.isHuman }.flatMap(\.cards).allSatisfy { $0 == .faceDown })
    }
}

@Test @MainActor func 公共牌逐张公布且减少动态仍保留发布顺序() async throws {
    for reduceMotion in [false, true] {
        let recorder = AnimationPublicationRecorder()
        let scenario = try await CoordinatorScenario.automaticSettlement(
            repository: FailOnceSessionRepository(failSettlementOnce: false),
            animationRecorder: nil,
            reduceMotion: reduceMotion,
            publicationRecorder: recorder
        )
        recorder.coordinator = scenario.coordinator
        try await scenario.playDeterministicallyToSettlement()
        await scenario.waitForAutomaticSettlement()

        let reveals = recorder.states.filter {
            $0.animation?.kind == .revealCommunityCard
        }
        #expect(reveals.count == 5)
        #expect(reveals.map(\.communityCards.count) == [1, 2, 3, 4, 5])
        #expect(reveals.allSatisfy { $0.phase == .revealingBoard && $0.controls == nil })
    }
}

@Test @MainActor func 真实摊牌后下一手发牌不继承旧底牌和公共牌() async throws {
    let recorder = AnimationPublicationRecorder()
    let scenario = try await CoordinatorScenario.automaticSettlement(
        repository: FailOnceSessionRepository(failSettlementOnce: false),
        reduceMotion: true,
        publicationRecorder: recorder
    )
    recorder.coordinator = scenario.coordinator
    try await scenario.playDeterministicallyToSettlement(preserveHumanStack: true)
    await scenario.waitForAutomaticSettlement()
    #expect(scenario.coordinator.state.phase == .awaitingNextHand)
    #expect(!scenario.coordinator.state.communityCards.isEmpty)
    recorder.reset()

    try await scenario.coordinator.startNextHand(settings: .recommended)

    let dealing = recorder.states.filter { $0.animation?.kind == .dealHoleCard }
    #expect(dealing.count == 18)
    for state in dealing {
        #expect(state.communityCards.isEmpty)
        #expect(state.seats.allSatisfy { $0.cards.count <= 2 })
        #expect(state.seats.filter { !$0.isHuman }.flatMap(\.cards).allSatisfy {
            $0 == .faceDown
        })
    }
    #expect(dealing.map { $0.seats.flatMap(\.cards).count } == Array(1...18))
}

@Test func 多个赢家的完整集合不依赖高亮播放进度() throws {
    let first = try SeatID(1)
    let second = try SeatID(4)
    let events: [PublicGameEvent] = [
        .potAwarded(
            potIndex: 0,
            winners: [second, first],
            amounts: [first: try Chips(50), second: try Chips(50)]
        ),
    ]

    #expect(CashTableAnimationMapper.completeWinnerSeats(in: events) == [first, second])
}
