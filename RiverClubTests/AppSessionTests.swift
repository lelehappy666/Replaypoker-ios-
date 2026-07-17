import Foundation
import PokerBot
import PokerCoordinator
import PokerCore
import PokerSession
import XCTest
@testable import RiverClub

final class AppSessionTests: XCTestCase {
    func testReducedMotionDisablesBuyInAnimation() {
        XCTAssertFalse(MotionPolicy.shouldAnimate(reduceMotion: true))
        XCTAssertTrue(MotionPolicy.shouldAnimate(reduceMotion: false))
    }

    func testSidebarKeepsHistoryAndTableBrowserIsNotSidebarItem() {
        XCTAssertEqual(AppRoute.sidebarRoutes, [.lobby, .tournaments, .tables, .profile])
        XCTAssertFalse(AppRoute.sidebarRoutes.contains(.tableBrowser))
    }

    func testHistoryDeletionModalDisablesAndHidesTheWholeAppShell() {
        let policy = AppRootModalPolicy(isHistoryDeletionPresented: true)

        XCTAssertFalse(policy.allowsBackgroundInteraction)
        XCTAssertTrue(policy.hidesBackgroundFromAccessibility)
    }

    func testTableDepartureModalDisablesAndHidesTheWholeAppShell() {
        let policy = AppRootModalPolicy(
            isHistoryDeletionPresented: false,
            isTableDeparturePresented: true
        )

        XCTAssertFalse(policy.allowsBackgroundInteraction)
        XCTAssertTrue(policy.hidesBackgroundFromAccessibility)
    }

    @MainActor
    func testUITestStoreIDsAreIsolatedAndRejectUnsafePaths() throws {
        let first = try AppSession.uiTestingStoreDirectory(storeID: "history-flow")
        let second = try AppSession.uiTestingStoreDirectory(storeID: "core-flow")

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, "history-flow")
        XCTAssertEqual(second.lastPathComponent, "core-flow")
        XCTAssertThrowsError(
            try AppSession.uiTestingStoreDirectory(storeID: "../escape")
        )
        XCTAssertThrowsError(
            try AppSession.uiTestingStoreDirectory(storeID: "含空格")
        )
        XCTAssertThrowsError(
            try AppSession.uiTestingStoreDirectory(storeID: "-openHistory")
        )
    }

    func testUITestFixtureOnlySleepsForShortAnimationDurations() {
        XCTAssertEqual(
            AppSession.uiTestingAnimationSleepDuration(for: .milliseconds(600)),
            .milliseconds(600)
        )
        XCTAssertEqual(
            AppSession.uiTestingAnimationSleepDuration(for: .milliseconds(700)),
            .milliseconds(700)
        )
        XCTAssertNil(AppSession.uiTestingAnimationSleepDuration(for: .milliseconds(701)))
        XCTAssertNil(AppSession.uiTestingAnimationSleepDuration(for: .zero))
    }

    @MainActor
    func testUITestIdentitySeedProducesDistinctEightPersonGroupsForSeparateEntries() throws {
        let session = try AppSession.uiTestingImmediate(
            resetHistoryStore: true,
            storeID: "identity-seed-fixture",
            identitySeed: 41
        )
        let humanSeat = try SeatID(8)
        let first = try session.uiTestingSeatProfiles(humanSeat: humanSeat)
        let second = try session.uiTestingSeatProfiles(humanSeat: humanSeat)
        let third = try session.uiTestingSeatProfiles(humanSeat: humanSeat)
        let fourth = try session.uiTestingSeatProfiles(humanSeat: humanSeat)

        let firstBots = first.filter { $0.id != humanSeat }.map { $0.displayName }
        let secondBots = second.filter { $0.id != humanSeat }.map { $0.displayName }
        XCTAssertEqual(firstBots.count, 8)
        XCTAssertEqual(Set(firstBots).count, 8)
        XCTAssertEqual(secondBots.count, 8)
        XCTAssertEqual(Set(secondBots).count, 8)
        XCTAssertNotEqual(firstBots, secondBots)
        XCTAssertEqual(Set(third.filter { $0.id != humanSeat }.map(\.displayName)).count, 8)
        XCTAssertEqual(Set(fourth.filter { $0.id != humanSeat }.map(\.displayName)).count, 8)
        XCTAssertNotEqual(secondBots, third.filter { $0.id != humanSeat }.map(\.displayName))
        XCTAssertEqual(firstBots, fourth.filter { $0.id != humanSeat }.map(\.displayName))
    }

    @MainActor
    func testGuestLoginOpensLobbyAndLogoutReturnsToLogin() throws {
        let session = try AppSessionFixture().session
        XCTAssertEqual(session.route, .login)
        session.continueAsGuest()
        XCTAssertEqual(session.route, .lobby)
        session.logout()
        XCTAssertEqual(session.route, .login)
    }

    @MainActor
    func testJoiningTableStoresSelectedTable() throws {
        let fixture = try AppSessionFixture()
        let session = fixture.session
        let table = fixture.table

        try session.joinCashTable(
            table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )

        XCTAssertEqual(session.route, .table)
        XCTAssertEqual(session.selectedTable, table)
    }

    func testTableHeaderUsesSelectedTableNameAndBlinds() {
        let table = makeTable(name: "星河湾", smallBlind: 200, bigBlind: 400)

        XCTAssertEqual(PokerTablePresentation.title(for: table), "星河湾 · 200 / 400")
    }

    @MainActor
    func testLeavingTableClearsSelectedTableAndRestoresRoute() throws {
        let fixture = try AppSessionFixture()
        let session = fixture.session
        try session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )

        session.leaveTable(returningTo: .tables)

        XCTAssertEqual(session.route, .tables)
        XCTAssertNil(session.selectedTable)
    }

    @MainActor
    func testDepartureConfirmationReturnsToEntryRouteAndRefundsOnce() async throws {
        let fixture = try AppSessionFixture()
        let session = fixture.session
        let balanceBefore = session.chipBalance
        session.open(.tableBrowser)
        try session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )

        session.requestTableDeparture()
        XCTAssertTrue(session.isTableDeparturePresented)
        XCTAssertFalse(session.isLeavingTable)

        await session.confirmTableDeparture()
        let balanceAfter = session.chipBalance

        XCTAssertEqual(session.route, .tableBrowser)
        XCTAssertNil(session.selectedTable)
        XCTAssertNil(session.tableCoordinator)
        XCTAssertFalse(session.isTableDeparturePresented)
        XCTAssertNil(session.tableDepartureError)
        XCTAssertEqual(balanceAfter, balanceBefore)

        await session.confirmTableDeparture()
        XCTAssertEqual(session.chipBalance, balanceAfter)
    }

    @MainActor
    func testCancellingDepartureKeepsCurrentTable() throws {
        let fixture = try AppSessionFixture()
        let session = fixture.session
        try session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false,
            reduceMotion: true
        )

        session.requestTableDeparture()
        session.cancelTableDeparture()

        XCTAssertEqual(session.route, .table)
        XCTAssertEqual(session.selectedTable, fixture.table)
        XCTAssertFalse(session.isTableDeparturePresented)
    }

    private func makeTable(name: String, smallBlind: Int, bigBlind: Int) -> PokerTableSummary {
        PokerTableSummary(
            id: UUID(),
            name: name,
            smallBlind: smallBlind,
            bigBlind: bigBlind,
            players: 6,
            capacity: 9,
            averagePot: 1_200,
            isFavorite: false
        )
    }
}

@MainActor
final class ArchiveMetadataCapture {
    private(set) var value: HandArchiveMetadata?

    func record(_ metadata: HandArchiveMetadata) {
        value = metadata
    }
}

@MainActor
final class AppSessionFixture {
    let directory: URL
    let store: LocalPokerStore
    let session: AppSession
    let table: PokerTableSummary
    private let archiveMetadataCapture: ArchiveMetadataCapture

    var capturedArchiveMetadata: HandArchiveMetadata? {
        archiveMetadataCapture.value
    }

    init(
        failingSave: Bool = false,
        botSettingsRepository: any BotSettingsPersisting = MemoryBotSettingsRepository(
            initial: .recommended
        ),
        dependencies: AppSessionDependencies? = nil,
        archiveMetadataCapture: ArchiveMetadataCapture = ArchiveMetadataCapture()
    ) throws {
        self.archiveMetadataCapture = archiveMetadataCapture
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("river-club-app-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        store = try LocalPokerStore.open(
            directory: directory,
            clock: FixedSessionClock(
                now: Date(timeIntervalSince1970: 1_800_000_000),
                day: try LocalDay("2027-01-15")
            )
        )
        if failingSave {
            try FileManager.default.removeItem(at: directory)
        }
        let liveDependencies = AppSessionDependencies.live
        let resolvedDependencies = dependencies ?? AppSessionDependencies(
            nextSessionID: liveDependencies.nextSessionID,
            nextBusinessID: liveDependencies.nextBusinessID,
            makeSeatProfiles: liveDependencies.makeSeatProfiles,
            makeRuntimeDependencies: liveDependencies.makeRuntimeDependencies,
            makeCoordinator: { store, humanSeat, profiles, archiveMetadata, runtime in
                archiveMetadataCapture.record(archiveMetadata)
                return try CashTableCoordinator(
                    store: store,
                    humanSeat: humanSeat,
                    seatProfiles: profiles,
                    archiveMetadata: archiveMetadata,
                    dependencies: runtime
                )
            }
        )
        session = AppSession(
            pokerStore: store,
            botSettingsRepository: botSettingsRepository,
            dependencies: resolvedDependencies
        )
        table = Self.makeTable()
    }

    nonisolated static func makeTable() -> PokerTableSummary {
        PokerTableSummary(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000010")!,
            name: "星河湾",
            smallBlind: 200,
            bigBlind: 400,
            players: 6,
            capacity: 9,
            averagePot: 1_200,
            isFavorite: false
        )
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
