import Foundation
import PokerBot
import PokerCoordinator
import PokerCore
import PokerSession
import XCTest
@testable import RiverClub

final class CashTableEntryTests: XCTestCase {
    @MainActor
    func testFailedSitDownKeepsBalanceAndRoute() throws {
        let fixture = try AppSessionFixture(failingSave: true)
        fixture.session.continueAsGuest()
        let before = fixture.session.chipBalance

        XCTAssertThrowsError(
            try fixture.session.joinCashTable(
                fixture.table,
                buyIn: 16_000,
                autoTopUp: false,
                reduceMotion: true
            )
        )

        XCTAssertEqual(fixture.session.chipBalance, before)
        XCTAssertEqual(fixture.session.route, .lobby)
        XCTAssertNil(fixture.session.tableCoordinator)
        XCTAssertNil(fixture.session.selectedTable)
    }

    @MainActor
    func testSuccessfulSitDownDeductsStoreBalanceAndEntersTable() throws {
        let fixture = try AppSessionFixture()
        fixture.session.continueAsGuest()
        let before = fixture.session.chipBalance

        try fixture.session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )

        XCTAssertEqual(fixture.session.chipBalance, before - 16_000)
        XCTAssertEqual(fixture.session.route, .table)
        XCTAssertEqual(fixture.session.selectedTable, fixture.table)
        XCTAssertNotNil(fixture.session.tableCoordinator)
    }

    func testNineProfilesAreUniqueAndMatchRequestSeats() throws {
        let table = AppSessionFixture.makeTable()
        let request = try CashTableRequestFactory.make(
            table: table,
            buyIn: 16_000,
            balance: 128_500,
            sessionID: try SessionID("profile-test")
        )
        let profiles = try TableSeatProfileFactory.make(humanSeat: request.humanSeat)

        XCTAssertEqual(request.stacks.count, 9)
        XCTAssertEqual(profiles.count, 9)
        XCTAssertEqual(Set(profiles.map(\.id)), Set(request.stacks.keys))
        XCTAssertEqual(Set(profiles.map(\.displayName)).count, 9)
    }

    @MainActor
    func testInvalidProfilesAreRejectedBeforeSitDownWithoutChangingState() throws {
        let request = try CashTableRequestFactory.make(
            table: AppSessionFixture.makeTable(),
            buyIn: 16_000,
            balance: 128_500,
            sessionID: try SessionID("invalid-profile-test")
        )
        let profiles = try TableSeatProfileFactory.make(humanSeat: request.humanSeat)
        let duplicateSeat = Array(profiles.dropLast()) + [profiles[0]]
        let duplicateName = try profiles.map { profile -> TableSeatProfile in
            if profile.id == request.humanSeat {
                return try TableSeatProfile(
                    id: profile.id,
                    displayName: profiles[0].displayName
                )
            }
            return profile
        }
        let invalidCases = [Array(profiles.dropLast()), duplicateSeat, duplicateName]

        for invalidProfiles in invalidCases {
            let fixture = try AppSessionFixture()
            fixture.session.continueAsGuest()
            let before = fixture.session.chipBalance

            XCTAssertThrowsError(
                try fixture.session.joinCashTable(
                    fixture.table,
                    buyIn: 16_000,
                    autoTopUp: false,
                    reduceMotion: true,
                    seatProfiles: invalidProfiles
                )
            )
            XCTAssertEqual(fixture.session.chipBalance, before)
            XCTAssertNil(fixture.store.cashSession)
            XCTAssertEqual(fixture.session.route, .lobby)
            XCTAssertNil(fixture.session.tableCoordinator)
        }
    }

    @MainActor
    func testJoinRejectsInvalidBuyInsBeforeGeneratingAttempt() throws {
        let invalidCases: [(PokerTableSummary, Int)] = [
            (AppSessionFixture.makeTable(), 15_600),
            (AppSessionFixture.makeTable(), 40_400),
            (makeTable(smallBlind: 2_000, bigBlind: 4_000), 160_000),
        ]

        for (table, buyIn) in invalidCases {
            let ids = JoinAttemptIDSpy()
            let fixture = try AppSessionFixture(dependencies: makeDependencies(ids: ids))
            fixture.session.continueAsGuest()
            let before = fixture.session.chipBalance

            XCTAssertThrowsError(
                try fixture.session.joinCashTable(
                    table,
                    buyIn: buyIn,
                    autoTopUp: false,
                    reduceMotion: true
                )
            )
            XCTAssertEqual(ids.sessionIDCalls, 0)
            XCTAssertEqual(ids.businessIDCalls, 0)
            XCTAssertEqual(fixture.session.chipBalance, before)
            XCTAssertNil(fixture.store.cashSession)
            XCTAssertEqual(fixture.session.route, .lobby)
            XCTAssertNil(fixture.session.tableCoordinator)
        }
    }

    @MainActor
    func testCoordinatorCreationRetryReusesAttemptWithoutSecondDeduction() throws {
        let ids = JoinAttemptIDSpy()
        var coordinatorCalls = 0
        let dependencies = makeDependencies(
            ids: ids,
            makeCoordinator: { store, humanSeat, profiles, runtime in
                coordinatorCalls += 1
                if coordinatorCalls == 1 {
                    throw CashTableEntryTestError.coordinatorCreation
                }
                return try CashTableCoordinator(
                    store: store,
                    humanSeat: humanSeat,
                    seatProfiles: profiles,
                    dependencies: runtime
                )
            }
        )
        let fixture = try AppSessionFixture(dependencies: dependencies)
        fixture.session.continueAsGuest()
        let table = makeTable(smallBlind: 642, bigBlind: 1_285)
        let buyIn = 128_500
        let before = fixture.session.chipBalance

        XCTAssertThrowsError(
            try fixture.session.joinCashTable(
                table,
                buyIn: buyIn,
                autoTopUp: false,
                reduceMotion: true
            )
        )
        let afterFirstAttempt = fixture.session.chipBalance
        XCTAssertEqual(afterFirstAttempt, 0)

        XCTAssertThrowsError(
            try fixture.session.joinCashTable(
                table,
                buyIn: 102_800,
                autoTopUp: false,
                reduceMotion: true
            )
        ) { error in
            XCTAssertEqual(
                error as? AppSessionError,
                .conflictingCashTableAttempt
            )
        }
        XCTAssertEqual(fixture.session.chipBalance, afterFirstAttempt)

        try fixture.session.joinCashTable(
            table,
            buyIn: buyIn,
            autoTopUp: false,
            reduceMotion: true
        )

        XCTAssertEqual(ids.sessionIDCalls, 1)
        XCTAssertEqual(ids.businessIDCalls, 1)
        XCTAssertEqual(coordinatorCalls, 2)
        XCTAssertEqual(fixture.session.chipBalance, afterFirstAttempt)
        XCTAssertEqual(before, buyIn)
        XCTAssertEqual(fixture.session.route, .table)
        XCTAssertNotNil(fixture.session.tableCoordinator)
    }

    @MainActor
    func testSuccessfulJoinAutomaticallyStartsHand() async throws {
        let ids = JoinAttemptIDSpy()
        let fixture = try AppSessionFixture(dependencies: makeDependencies(ids: ids))

        try fixture.session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )
        await fixture.session.startOrResumeTableHand()

        XCTAssertEqual(fixture.store.cashSession?.phase, .handInProgress)
        XCTAssertNil(fixture.session.tableStartupError)
        XCTAssertEqual(ids.sessionIDCalls, 1)
        XCTAssertEqual(ids.businessIDCalls, 1)
    }

    @MainActor
    func testRepeatedStartRequestKeepsHealthyHandRunning() async throws {
        let ids = JoinAttemptIDSpy()
        let fixture = try AppSessionFixture(dependencies: makeDependencies(ids: ids))
        try fixture.session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )
        await fixture.session.startOrResumeTableHand()
        let phase = fixture.session.tableCoordinator?.state.phase

        await fixture.session.startOrResumeTableHand()

        XCTAssertEqual(fixture.store.cashSession?.phase, .handInProgress)
        XCTAssertEqual(fixture.session.tableCoordinator?.state.phase, phase)
        XCTAssertNotEqual(fixture.session.tableCoordinator?.state.phase, .suspended)
        XCTAssertNil(fixture.session.tableStartupError)
    }

    @MainActor
    func testStartupFailureIsVisibleAndRetryResumesSameHand() async throws {
        let ids = JoinAttemptIDSpy()
        let dependencies = makeDependencies(
            ids: ids,
            sleep: { _ in throw CashTableEntryTestError.animationSleep }
        )
        let fixture = try AppSessionFixture(dependencies: dependencies)
        let before = fixture.session.chipBalance

        try fixture.session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )
        await fixture.session.startOrResumeTableHand()

        XCTAssertEqual(fixture.store.cashSession?.phase, .handInProgress)
        XCTAssertEqual(fixture.session.tableCoordinator?.state.phase, .suspended)
        XCTAssertEqual(fixture.session.tableStartupError, "牌局启动失败，请重试。")
        let presentation = TableStartupRecoveryPresentation(
            errorMessage: fixture.session.tableStartupError
        )
        XCTAssertEqual(presentation?.message, "牌局启动失败，请重试。")
        XCTAssertEqual(presentation?.retryTitle, "重试牌局")
        let afterBuyIn = fixture.session.chipBalance

        await fixture.session.startOrResumeTableHand()

        XCTAssertNil(fixture.session.tableStartupError)
        XCTAssertNotEqual(fixture.session.tableCoordinator?.state.phase, .suspended)
        XCTAssertEqual(fixture.store.cashSession?.phase, .handInProgress)
        XCTAssertEqual(afterBuyIn, before - 16_000)
        XCTAssertEqual(fixture.session.chipBalance, afterBuyIn)
        XCTAssertEqual(ids.sessionIDCalls, 1)
        XCTAssertEqual(ids.businessIDCalls, 1)
    }

    @MainActor
    func testLocalNextHandFailureRetriesByResumingSameHand() async throws {
        let ids = JoinAttemptIDSpy()
        let dependencies = makeDependencies(
            ids: ids,
            sleep: { _ in throw CashTableEntryTestError.animationSleep }
        )
        let fixture = try AppSessionFixture(dependencies: dependencies)
        fixture.session.continueAsGuest()
        try fixture.session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )
        let coordinator = try XCTUnwrap(fixture.session.tableCoordinator)
        let model = TableActionRequestModel()
        let balanceAfterBuyIn = fixture.session.chipBalance

        await model.send(.nextHand) { _ in
            try await coordinator.startHand(settings: .recommended)
        }

        XCTAssertEqual(fixture.store.cashSession?.phase, .handInProgress)
        XCTAssertEqual(coordinator.state.phase, .suspended)
        XCTAssertEqual(model.errorMessage, "操作失败，请重试。")
        XCTAssertNil(fixture.session.tableStartupError)
        let handID = coordinator.state.handID
        var sendCalls = 0
        var resumeCalls = 0

        await model.retry(
            for: coordinator.state.phase,
            send: { intent in
                sendCalls += 1
                try await coordinator.send(intent)
            },
            resume: {
                resumeCalls += 1
                try await coordinator.resume()
            }
        )

        XCTAssertEqual(sendCalls, 0)
        XCTAssertEqual(resumeCalls, 1)
        XCTAssertNil(model.errorMessage)
        XCTAssertNotEqual(coordinator.state.phase, .suspended)
        XCTAssertEqual(coordinator.state.handID, handID)
        XCTAssertEqual(fixture.session.chipBalance, balanceAfterBuyIn)
        XCTAssertNil(fixture.session.tableStartupError)
    }

    @MainActor
    func testNextHandIntentFreezesLatestAppSettingsBeforeStartingRealCoordinator() async throws {
        let fixture = try AppSessionFixture()
        try fixture.session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )
        let latest = try BotSettings(
            difficulty: .hard,
            model: .aggressive,
            aggression: 80,
            bluffFrequency: 45,
            callingWidth: 60,
            betSizing: 70,
            thinkingSpeed: .fast,
            analyzesHistory: false
        )
        try fixture.session.saveBotSettings(latest)

        try await fixture.session.sendTableIntent(.nextHand)

        XCTAssertEqual(fixture.session.frozenBotSettings, latest)
        XCTAssertEqual(fixture.store.cashSession?.phase, .handInProgress)
    }

    @MainActor
    func testLifecyclePauseAndResumeKeepsSameHandWithoutBackgroundProgress() async throws {
        let ids = JoinAttemptIDSpy()
        let clock = AppLifecycleManualClock()
        let fixture = try AppSessionFixture(
            dependencies: makeDependencies(ids: ids, sleep: clock.sleep)
        )
        try fixture.session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )
        await fixture.session.startOrResumeTableHand()
        let coordinator = try XCTUnwrap(fixture.session.tableCoordinator)
        let handID = coordinator.state.handID
        let actions = try XCTUnwrap(try fixture.store.humanObservation()).actions.count

        fixture.session.suspendTableForLifecycle()
        await clock.advance(seconds: 60)
        XCTAssertEqual(coordinator.state.phase, .suspended)
        XCTAssertEqual(try fixture.store.humanObservation()?.actions.count, actions)

        await fixture.session.resumeTableForLifecycle()
        XCTAssertEqual(coordinator.state.handID, handID)
        XCTAssertNotEqual(coordinator.state.phase, .suspended)
    }
}

private actor AppLifecycleManualClock {
    func sleep(_ duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }

    func advance(seconds: Int) async {
        for _ in 0..<seconds { await Task.yield() }
    }
}

@MainActor
private final class JoinAttemptIDSpy {
    private(set) var sessionIDCalls = 0
    private(set) var businessIDCalls = 0

    func nextSessionID() throws -> SessionID {
        sessionIDCalls += 1
        return try SessionID("join-session-\(sessionIDCalls)")
    }

    func nextBusinessID(_ purpose: String) throws -> BusinessID {
        businessIDCalls += 1
        return try BusinessID("\(purpose)-\(businessIDCalls)")
    }
}

@MainActor
private func makeDependencies(
    ids: JoinAttemptIDSpy,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in },
    makeCoordinator: (@MainActor (
        LocalPokerStore,
        SeatID,
        [TableSeatProfile],
        TableRuntimeDependencies
    ) throws -> CashTableCoordinator)? = nil
) -> AppSessionDependencies {
    AppSessionDependencies(
        nextSessionID: ids.nextSessionID,
        nextBusinessID: ids.nextBusinessID,
        makeRuntimeDependencies: { _ in
            TableRuntimeDependencies(
                nextHandID: { try HandID("app-session-hand") },
                nextBusinessID: { purpose in try BusinessID("\(purpose)-app-session") },
                nextSeed: { 37 },
                sleep: sleep,
                reduceMotion: true
            )
        },
        makeCoordinator: makeCoordinator ?? { store, humanSeat, profiles, runtime in
            try CashTableCoordinator(
                store: store,
                humanSeat: humanSeat,
                seatProfiles: profiles,
                dependencies: runtime
            )
        }
    )
}

private func makeTable(smallBlind: Int, bigBlind: Int) -> PokerTableSummary {
    PokerTableSummary(
        id: UUID(),
        name: "高额桌",
        smallBlind: smallBlind,
        bigBlind: bigBlind,
        players: 6,
        capacity: 9,
        averagePot: 20_000,
        isFavorite: false
    )
}

private enum CashTableEntryTestError: Error {
    case coordinatorCreation
    case animationSleep
}
