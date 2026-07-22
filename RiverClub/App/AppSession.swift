import Foundation
import Observation
import PokerBot
import PokerCoordinator
import PokerCore
import PokerSession

enum AppRoute: Equatable {
    case login, lobby, tables, tableBrowser, table, tournaments, profile
}

extension AppRoute {
    static let sidebarRoutes: [AppRoute] = [.lobby, .tournaments, .tables, .profile]
}

enum AppSessionError: Error, Equatable {
    case conflictingCashTableAttempt
    case unsettledCashSession
    case invalidUITestStoreID
}

@MainActor
struct AppSessionDependencies {
    let nextSessionID: () throws -> SessionID
    let nextBusinessID: (_ purpose: String) throws -> BusinessID
    let makeSeatProfiles: (_ humanSeat: SeatID) throws -> [TableSeatProfile]
    let makeRuntimeDependencies: (_ reduceMotion: Bool) -> TableRuntimeDependencies
    let makeCoordinator: (
        _ store: LocalPokerStore,
        _ humanSeat: SeatID,
        _ profiles: [TableSeatProfile],
        _ archiveMetadata: HandArchiveMetadata,
        _ runtime: TableRuntimeDependencies
    ) throws -> CashTableCoordinator
    var loadHandRecords: (LocalPokerStore, HandRecordFilter) throws -> [StoredHandRecord]
    var deleteHandRecord: (LocalPokerStore, HandID) throws -> Void
    var deleteAllHandRecords: (LocalPokerStore) throws -> Void
    var currentLocalDay: () -> LocalDay

    init(
        nextSessionID: @escaping () throws -> SessionID,
        nextBusinessID: @escaping (_ purpose: String) throws -> BusinessID,
        makeSeatProfiles: @escaping (_ humanSeat: SeatID) throws -> [TableSeatProfile],
        makeRuntimeDependencies: @escaping (
            _ reduceMotion: Bool
        ) -> TableRuntimeDependencies,
        makeCoordinator: @escaping (
            _ store: LocalPokerStore,
            _ humanSeat: SeatID,
            _ profiles: [TableSeatProfile],
            _ archiveMetadata: HandArchiveMetadata,
            _ runtime: TableRuntimeDependencies
        ) throws -> CashTableCoordinator,
        loadHandRecords: @escaping (
            LocalPokerStore,
            HandRecordFilter
        ) throws -> [StoredHandRecord] = { store, filter in
            store.handRecords(filter: filter)
        },
        deleteHandRecord: @escaping (LocalPokerStore, HandID) throws -> Void = {
            store, id in
            try store.deleteHand(id: id)
        },
        deleteAllHandRecords: @escaping (LocalPokerStore) throws -> Void = { store in
            try store.deleteAllHands(confirmation: .confirmed)
        },
        currentLocalDay: @escaping () -> LocalDay = {
            AppSessionClock().currentDay
        }
    ) {
        self.nextSessionID = nextSessionID
        self.nextBusinessID = nextBusinessID
        self.makeSeatProfiles = makeSeatProfiles
        self.makeRuntimeDependencies = makeRuntimeDependencies
        self.makeCoordinator = makeCoordinator
        self.loadHandRecords = loadHandRecords
        self.deleteHandRecord = deleteHandRecord
        self.deleteAllHandRecords = deleteAllHandRecords
        self.currentLocalDay = currentLocalDay
    }

    static var live: Self {
        Self(
            nextSessionID: { try SessionID(UUID().uuidString) },
            nextBusinessID: { purpose in
                try BusinessID("\(purpose):\(UUID().uuidString)")
            },
            makeSeatProfiles: TableSeatProfileFactory.make,
            makeRuntimeDependencies: TableRuntimeDependencies.live,
            makeCoordinator: { store, humanSeat, profiles, archiveMetadata, runtime in
                try CashTableCoordinator(
                    store: store,
                    humanSeat: humanSeat,
                    seatProfiles: profiles,
                    archiveMetadata: archiveMetadata,
                    dependencies: runtime
                )
            }
        )
    }
}

private struct CashTableJoinAttempt {
    let table: PokerTableSummary
    let buyIn: Int
    let autoTopUp: Bool
    let request: CashTableRequest
    let businessID: BusinessID
    let profiles: [TableSeatProfile]

    func matches(
        table: PokerTableSummary,
        buyIn: Int,
        autoTopUp: Bool,
        profiles: [TableSeatProfile]?
    ) -> Bool {
        self.table == table
            && self.buyIn == buyIn
            && self.autoTopUp == autoTopUp
            && (profiles == nil || profiles == self.profiles)
    }
}

private struct TableDepartureAttempt {
    let settlementID: BusinessID
    let cashOutID: BusinessID
}

private struct AbandonedCashSessionSettlementAttempt {
    let settlementID: BusinessID
    let cashOutID: BusinessID
    let profiles: [TableSeatProfile]
}

@MainActor @Observable
final class AppSession {
    private static let currentWelcomeBalanceTopUpVersion = 1
    private static let currentWelcomeBalanceTopUpBusinessID =
        "river-club:welcome-balance-top-up:v1"

    var route: AppRoute = .login
    @ObservationIgnored let pokerStore: LocalPokerStore
    private(set) var tableCoordinator: CashTableCoordinator?
    private(set) var botSettings: BotSettings
    private(set) var frozenBotSettings: BotSettings?
    private(set) var botSettingsError: String?
    private(set) var tableExperienceSettings: TableExperienceSettings
    private(set) var tableExperienceSettingsError: String?
    private(set) var tableStartupError: String?
    private(set) var isTableDeparturePresented = false
    private(set) var isLeavingTable = false
    private(set) var tableDepartureError: String?
    private(set) var isSettlingAbandonedCashSession = false
    private(set) var abandonedCashSessionError: String?
    private(set) var handHistoryState = HandHistoryViewState()
    @ObservationIgnored private let botSettingsRepository: any BotSettingsPersisting
    @ObservationIgnored private let tableExperienceSettingsRepository:
        any TableExperienceSettingsPersisting
    @ObservationIgnored private let dependencies: AppSessionDependencies
    private var tableState = TableSessionState()
    private var cashTableJoinAttempt: CashTableJoinAttempt?
    private var tableDepartureAttempt: TableDepartureAttempt?
    private var abandonedCashSessionSettlementAttempt:
        AbandonedCashSessionSettlementAttempt?
    private var tableReturnRoute: AppRoute = .lobby
    private var isStartingOrResumingTableHand = false

    var chipBalance: Int { pokerStore.accountBalance.rawValue }
    var selectedTable: PokerTableSummary? { tableState.selectedTable }
    var hasUnsettledCashSession: Bool {
        pokerStore.cashSession != nil
            && tableCoordinator == nil
            && cashTableJoinAttempt == nil
    }

    init(
        pokerStore: LocalPokerStore,
        botSettingsRepository: any BotSettingsPersisting,
        tableExperienceSettingsRepository: any TableExperienceSettingsPersisting =
            MemoryTableExperienceSettingsRepository(),
        dependencies: AppSessionDependencies = .live
    ) {
        self.pokerStore = pokerStore
        self.botSettingsRepository = botSettingsRepository
        self.tableExperienceSettingsRepository = tableExperienceSettingsRepository
        self.dependencies = dependencies
        do {
            botSettings = try botSettingsRepository.load()
            botSettingsError = nil
        } catch {
            botSettings = .recommended
            botSettingsError = "机器人设置读取失败，请检查设置文件或恢复推荐设置。"
        }
        do {
            tableExperienceSettings = try tableExperienceSettingsRepository.load()
            tableExperienceSettingsError = nil
        } catch {
            tableExperienceSettings = .recommended
            tableExperienceSettingsError = "牌桌设置读取失败，已使用推荐设置。"
        }
    }

    static func live() throws -> AppSession {
        let fileManager = FileManager.default
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let support = root.appendingPathComponent("RiverClub", isDirectory: true)
        let sessionDirectory = support.appendingPathComponent(
            "PokerSession",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: true
        )
        return try openPersistedSession(
            directory: sessionDirectory,
            clock: AppSessionClock(),
            botSettingsRepository: try BotSettingsRepository.applicationSupport(),
            tableExperienceSettingsRepository: TableExperienceSettingsRepository(),
            dependencies: .live
        )
    }

    static func openPersistedSession(
        directory: URL,
        clock: any SessionClock,
        botSettingsRepository: any BotSettingsPersisting,
        tableExperienceSettingsRepository: any TableExperienceSettingsPersisting =
            TableExperienceSettingsRepository(),
        dependencies: AppSessionDependencies
    ) throws -> AppSession {
        let store = try LocalPokerStore.open(
            directory: directory,
            clock: clock
        )
        _ = try applyCurrentWelcomeBalanceTopUp(to: store)
        return AppSession(
            pokerStore: store,
            botSettingsRepository: botSettingsRepository,
            tableExperienceSettingsRepository: tableExperienceSettingsRepository,
            dependencies: dependencies
        )
    }

    static func applyCurrentWelcomeBalanceTopUp(
        to store: LocalPokerStore
    ) throws -> LedgerEntry {
        try store.claimWelcomeBalanceTopUp(
            version: currentWelcomeBalanceTopUpVersion,
            businessID: try BusinessID(currentWelcomeBalanceTopUpBusinessID)
        )
    }

    static func uiTestingStoreDirectory(storeID: String) throws -> URL {
        let fileManager = FileManager.default
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        )
        guard !storeID.isEmpty,
              !storeID.hasPrefix("-"),
              storeID.count <= 64,
              storeID.unicodeScalars.allSatisfy(allowed.contains)
        else {
            throw AppSessionError.invalidUITestStoreID
        }
        return fileManager.temporaryDirectory
            .appendingPathComponent(
            "RiverClub-Immediate-UITests",
            isDirectory: true
        )
            .appendingPathComponent(storeID, isDirectory: true)
    }

    static func uiTestingImmediate(
        resetHistoryStore: Bool,
        storeID: String,
        identitySeed: UInt64? = nil
    ) throws -> AppSession {
        let fileManager = FileManager.default
        let directory = try uiTestingStoreDirectory(storeID: storeID)
        if resetHistoryStore, fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let ids = UITestIDSequence(namespace: UUID().uuidString)
        let identitySequence = identitySeed.map(UITestIdentityProfileSequence.init)
        return try openPersistedSession(
            directory: directory,
            clock: AppSessionClock(),
            botSettingsRepository: MemoryBotSettingsRepository(initial: .recommended),
            tableExperienceSettingsRepository:
                MemoryTableExperienceSettingsRepository(),
            dependencies: AppSessionDependencies(
                nextSessionID: {
                    try SessionID(ids.nextSessionID())
                },
                nextBusinessID: { purpose in
                    try BusinessID(
                        "ui:\(purpose):\(ids.nextBusinessID())"
                    )
                },
                makeSeatProfiles: { humanSeat in
                    if let identitySequence {
                        return try identitySequence.next(humanSeat: humanSeat)
                    }
                    return try TableSeatProfileFactory.make(humanSeat: humanSeat)
                },
                makeRuntimeDependencies: { _ in
                    TableRuntimeDependencies(
                        nextHandID: { try HandID(ids.nextHandID()) },
                        nextBusinessID: { purpose in
                            try BusinessID("ui:\(purpose):\(ids.nextBusinessID())")
                        },
                        nextSeed: { 37 },
                        sleep: { duration in
                            if let animationDuration = uiTestingAnimationSleepDuration(for: duration) {
                                try await ContinuousClock().sleep(for: animationDuration)
                            } else if duration > .zero {
                                try await ContinuousClock().sleep(for: .seconds(300))
                            }
                        },
                        reduceMotion: true
                    )
                },
                makeCoordinator: { store, humanSeat, profiles, archiveMetadata, runtime in
                    try CashTableCoordinator(
                        store: store,
                        humanSeat: humanSeat,
                        seatProfiles: profiles,
                        archiveMetadata: archiveMetadata,
                        dependencies: runtime
                    )
                }
            )
        )
    }

    nonisolated static func uiTestingAnimationSleepDuration(for duration: Duration) -> Duration? {
        guard duration > .zero, duration <= .milliseconds(700) else { return nil }
        return duration
    }

    #if DEBUG
    func uiTestingSeatProfiles(humanSeat: SeatID) throws -> [TableSeatProfile] {
        try dependencies.makeSeatProfiles(humanSeat)
    }

    #endif

    func continueAsGuest() { route = .lobby }
    func logout() { route = .login }
    func open(_ route: AppRoute) {
        self.route = route
        if route == .tables {
            loadHandHistory()
        }
    }

    func updateHandHistoryFilters(_ filters: HandHistoryFilters) {
        if filters != handHistoryState.filters {
            handHistoryState.listScrollTarget = nil
        }
        handHistoryState.filters = filters
        loadHandHistory()
    }

    func beginCustomHandHistoryDateSelection() {
        updateHandHistoryFilters(
            HandHistoryFilters(
                table: handHistoryState.filters.table,
                dateSelection: .custom(dependencies.currentLocalDay())
            )
        )
    }

    func selectCustomHandHistoryDate(
        _ date: Date,
        calendar: Calendar
    ) throws {
        let day = try HandHistoryCustomDatePolicy.localDay(
            from: date,
            calendar: calendar
        )
        updateHandHistoryFilters(
            HandHistoryFilters(
                table: handHistoryState.filters.table,
                dateSelection: .custom(day)
            )
        )
    }

    func loadHandHistory() {
        handHistoryState.loadState = .loading
        handHistoryState.globalRecordCount = nil
        do {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .autoupdatingCurrent
            let filter = try HandHistoryPresentation.storeFilter(
                filters: handHistoryState.filters,
                today: dependencies.currentLocalDay(),
                calendar: calendar
            )
            let directoryItems = try dependencies
                .loadHandRecords(pokerStore, HandRecordFilter())
                .map { try HandHistoryPresentation.listItem(from: $0) }
            let records = try dependencies.loadHandRecords(pokerStore, filter)
            let items = try records.map {
                try HandHistoryPresentation.listItem(from: $0)
            }
            handHistoryState.availableTables = Self.historyTableOptions(
                from: directoryItems
            )
            handHistoryState.globalRecordCount = directoryItems.count
            if let target = handHistoryState.listScrollTarget,
               !items.contains(where: { $0.id == target }) {
                handHistoryState.listScrollTarget = nil
            }
            handHistoryState.loadState = .loaded(items)
        } catch {
            handHistoryState.globalRecordCount = nil
            handHistoryState.loadState = .failed("牌局存档读取失败，请重试。")
        }
    }

    func selectHandHistory(id: HandID) {
        do {
            guard let record = pokerStore.handRecords().first(where: { $0.id == id }) else {
                handHistoryState.selection = nil
                return
            }
            handHistoryState.listScrollTarget = id
            handHistoryState.selection = try HandHistoryPresentation.detail(from: record)
        } catch {
            handHistoryState.selection = nil
        }
    }

    func closeHandHistoryDetail() {
        handHistoryState.selection = nil
    }

    func updateHandHistoryScrollTarget(_ id: HandID?) {
        handHistoryState.listScrollTarget = id
    }

    func requestDeleteHand(id: HandID) {
        handHistoryState.pendingDeletion = .hand(id)
        handHistoryState.deletionError = nil
    }

    func requestDeleteAllHistory() {
        guard handHistoryState.canDeleteAll else { return }
        handHistoryState.pendingDeletion = .all
        handHistoryState.deletionError = nil
    }

    func cancelHistoryDeletion() {
        handHistoryState.pendingDeletion = nil
        handHistoryState.deletionError = nil
    }

    func confirmHistoryDeletion() throws {
        guard let pendingDeletion = handHistoryState.pendingDeletion else { return }
        do {
            switch pendingDeletion {
            case let .hand(id):
                try dependencies.deleteHandRecord(pokerStore, id)
            case .all:
                try dependencies.deleteAllHandRecords(pokerStore)
            }
        } catch {
            handHistoryState.deletionError = "牌局存档删除失败，请重试。"
            throw error
        }

        handHistoryState.pendingDeletion = nil
        handHistoryState.selection = nil
        handHistoryState.deletionError = nil
        loadHandHistory()
    }

    private static func historyTableOptions(
        from items: [HandHistoryListItem]
    ) -> [HandHistoryTableOption] {
        var namesByID: [TableID: String] = [:]
        for item in items where namesByID[item.tableID] == nil {
            namesByID[item.tableID] = item.tableName
        }
        return namesByID
            .map { HandHistoryTableOption(id: $0.key, name: $0.value) }
            .sorted {
                if $0.name == $1.name { return $0.id.rawValue < $1.id.rawValue }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    func joinCashTable(
        _ table: PokerTableSummary,
        buyIn: Int,
        autoTopUp: Bool,
        reduceMotion: Bool = false,
        seatProfiles: [TableSeatProfile]? = nil
    ) throws {
        let attempt: CashTableJoinAttempt
        if let existing = cashTableJoinAttempt {
            guard existing.matches(
                table: table,
                buyIn: buyIn,
                autoTopUp: autoTopUp,
                profiles: seatProfiles
            ) else {
                throw AppSessionError.conflictingCashTableAttempt
            }
            attempt = existing
        } else {
            guard pokerStore.cashSession == nil else {
                throw AppSessionError.unsettledCashSession
            }
            tableReturnRoute = route == .table ? .lobby : route
            try CashTableRequestFactory.validate(
                table: table,
                buyIn: buyIn,
                balance: chipBalance
            )
            let request = try CashTableRequestFactory.make(
                table: table,
                buyIn: buyIn,
                balance: chipBalance,
                sessionID: try dependencies.nextSessionID()
            )
            let profiles = try seatProfiles
                ?? dependencies.makeSeatProfiles(request.humanSeat)
            try CashTableCoordinator.validateSeatProfiles(
                profiles,
                matching: Array(request.stacks.keys),
                humanSeat: request.humanSeat
            )
            attempt = CashTableJoinAttempt(
                table: table,
                buyIn: buyIn,
                autoTopUp: autoTopUp,
                request: request,
                businessID: try dependencies.nextBusinessID(
                    "sit-down:\(request.sessionID.rawValue)"
                ),
                profiles: profiles
            )
            cashTableJoinAttempt = attempt
        }
        _ = try pokerStore.sitDown(
            request: attempt.request,
            businessID: attempt.businessID
        )
        let archiveMetadata = try HandArchiveMetadata(
            tableDisplayName: attempt.table.name,
            humanSeat: attempt.request.humanSeat,
            seatDisplayNames: Dictionary(
                uniqueKeysWithValues: attempt.profiles.map { ($0.id, $0.displayName) }
            ),
            seatAvatarAssetNames: Dictionary(
                uniqueKeysWithValues: attempt.profiles.map {
                    ($0.id, $0.avatarAssetName)
                }
            )
        )
        let coordinator = try dependencies.makeCoordinator(
            pokerStore,
            attempt.request.humanSeat,
            attempt.profiles,
            archiveMetadata,
            dependencies.makeRuntimeDependencies(reduceMotion)
        )
        tableCoordinator = coordinator
        tableState.enter(table)
        tableStartupError = nil
        route = .table
    }

    func settleAbandonedCashSessionIfNeeded() async {
        guard hasUnsettledCashSession,
              !isSettlingAbandonedCashSession,
              let cashSession = pokerStore.cashSession
        else {
            if pokerStore.cashSession == nil {
                abandonedCashSessionSettlementAttempt = nil
                abandonedCashSessionError = nil
            }
            return
        }

        isSettlingAbandonedCashSession = true
        abandonedCashSessionError = nil
        defer { isSettlingAbandonedCashSession = false }

        do {
            if abandonedCashSessionSettlementAttempt == nil {
                abandonedCashSessionSettlementAttempt =
                    AbandonedCashSessionSettlementAttempt(
                        settlementID: try dependencies.nextBusinessID(
                            "abandoned-settlement"
                        ),
                        cashOutID: try dependencies.nextBusinessID(
                            "abandoned-cash-out"
                        ),
                        profiles: try dependencies.makeSeatProfiles(
                            cashSession.humanSeat
                        )
                    )
            }
            guard let attempt = abandonedCashSessionSettlementAttempt else {
                throw PokerCoordinatorError.saveFailed
            }
            let profiles = attempt.profiles
            let archiveMetadata = try HandArchiveMetadata(
                tableDisplayName: "上次牌桌",
                humanSeat: cashSession.humanSeat,
                seatDisplayNames: Dictionary(
                    uniqueKeysWithValues: profiles.map {
                        ($0.id, $0.displayName)
                    }
                ),
                seatAvatarAssetNames: Dictionary(
                    uniqueKeysWithValues: profiles.map {
                        ($0.id, $0.avatarAssetName)
                    }
                )
            )
            let coordinator = try dependencies.makeCoordinator(
                pokerStore,
                cashSession.humanSeat,
                profiles,
                archiveMetadata,
                dependencies.makeRuntimeDependencies(true)
            )
            try await coordinator.leaveTable(
                settlementID: attempt.settlementID,
                cashOutID: attempt.cashOutID
            )
            abandonedCashSessionSettlementAttempt = nil
            abandonedCashSessionError = nil
        } catch {
            abandonedCashSessionError = "上次牌桌结算失败，请重试。"
        }
    }

    func retryAbandonedCashSessionSettlement() async {
        await settleAbandonedCashSessionIfNeeded()
    }

    func startOrResumeTableHand() async {
        guard !isStartingOrResumingTableHand else { return }
        guard let tableCoordinator else {
            tableStartupError = "牌局启动失败，请重试。"
            return
        }
        if pokerStore.cashSession?.phase != .readyForHand,
           tableCoordinator.state.phase != .suspended {
            tableStartupError = nil
            return
        }

        isStartingOrResumingTableHand = true
        defer { isStartingOrResumingTableHand = false }
        tableStartupError = nil
        do {
            if pokerStore.cashSession?.phase == .readyForHand {
                try await tableCoordinator.startHand(
                    settings: freezeBotSettingsForNextHand()
                )
            } else {
                try await tableCoordinator.resume()
            }
            tableStartupError = nil
        } catch {
            if tableCoordinator.state.phase != .suspended {
                tableCoordinator.suspend()
            }
            tableStartupError = "牌局启动失败，请重试。"
        }
    }

    func sendTableIntent(_ intent: TableIntent) async throws {
        guard let tableCoordinator else {
            throw PokerCoordinatorError.invalidPhase
        }
        if intent == .nextHand {
            try rebuyBustedHumanIfNeeded()
            try await tableCoordinator.startNextHand(
                settings: freezeBotSettingsForNextHand()
            )
        } else {
            try await tableCoordinator.send(intent)
        }
    }

    /// 点击“下一手”代表玩家选择继续；若上一手刚好输光，先从账户余额
    /// 补充该牌桌允许的最低买入，避免以零筹码启动牌局而弹出通用失败。
    private func rebuyBustedHumanIfNeeded() throws {
        guard let session = pokerStore.cashSession,
              let selectedTable,
              let human = session.seats.first(where: { $0.id == session.humanSeat }),
              human.stack.rawValue == 0
        else {
            return
        }
        let (minimumBuyIn, overflow) = selectedTable.bigBlind.multipliedReportingOverflow(
            by: SessionEconomy.minimumBuyInBigBlinds
        )
        guard !overflow,
              minimumBuyIn > 0,
              pokerStore.accountBalance.rawValue >= minimumBuyIn
        else {
            throw PokerSessionError.insufficientBalance
        }
        _ = try pokerStore.rebuyHuman(
            amount: try Chips(minimumBuyIn),
            businessID: try dependencies.nextBusinessID(
                "next-hand-rebuy:\(session.id.rawValue)"
            )
        )
    }

    func suspendTableForLifecycle() {
        guard route == .table else { return }
        tableCoordinator?.suspend()
    }

    func resumeTableForLifecycle() async {
        guard route == .table,
              let tableCoordinator,
              tableCoordinator.state.phase == .suspended
        else { return }
        do {
            try await tableCoordinator.resume()
            tableStartupError = nil
        } catch {
            tableStartupError = "牌局恢复失败，请重试。"
        }
    }

    func leaveTable(returningTo route: AppRoute) {
        tableState.leave()
        tableCoordinator = nil
        cashTableJoinAttempt = nil
        tableDepartureAttempt = nil
        isTableDeparturePresented = false
        isLeavingTable = false
        tableDepartureError = nil
        tableStartupError = nil
        open(route)
    }

    func requestTableDeparture() {
        guard route == .table, tableCoordinator != nil, !isLeavingTable else {
            return
        }
        isTableDeparturePresented = true
        tableDepartureError = nil
    }

    func cancelTableDeparture() {
        guard !isLeavingTable else { return }
        isTableDeparturePresented = false
        tableDepartureError = nil
    }

    func confirmTableDeparture() async {
        guard isTableDeparturePresented,
              !isLeavingTable,
              let tableCoordinator
        else {
            return
        }

        do {
            if tableDepartureAttempt == nil {
                tableDepartureAttempt = TableDepartureAttempt(
                    settlementID: try dependencies.nextBusinessID(
                        "departure-settlement"
                    ),
                    cashOutID: try dependencies.nextBusinessID(
                        "departure-cash-out"
                    )
                )
            }
            guard let attempt = tableDepartureAttempt else {
                throw PokerCoordinatorError.saveFailed
            }

            isLeavingTable = true
            tableDepartureError = nil
            try await tableCoordinator.leaveTable(
                settlementID: attempt.settlementID,
                cashOutID: attempt.cashOutID
            )

            tableState.leave()
            self.tableCoordinator = nil
            cashTableJoinAttempt = nil
            tableDepartureAttempt = nil
            isTableDeparturePresented = false
            isLeavingTable = false
            tableStartupError = nil
            open(tableReturnRoute)
        } catch {
            isLeavingTable = false
            tableDepartureError = "离桌结算失败，请重试。"
        }
    }

    func saveBotSettings(_ settings: BotSettings) throws {
        try botSettingsRepository.save(settings)
        botSettings = settings
        botSettingsError = nil
    }

    func saveTableExperienceSettings(
        _ settings: TableExperienceSettings
    ) throws {
        do {
            try tableExperienceSettingsRepository.save(settings)
            tableExperienceSettings = settings
            tableExperienceSettingsError = nil
        } catch {
            tableExperienceSettingsError = "牌桌设置保存失败，请重试。"
            throw error
        }
    }

    @discardableResult
    func restoreRecommendedBotSettings(confirmed: Bool) throws -> Bool {
        guard confirmed else { return false }
        botSettings = try botSettingsRepository.restoreRecommended()
        botSettingsError = nil
        return true
    }

    @discardableResult
    func freezeBotSettingsForNextHand() -> BotSettings {
        frozenBotSettings = botSettings
        return botSettings
    }
}

private final class UITestIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let namespace: String
    private var session = 0
    private var hand = 0
    private var business = 0

    init(namespace: String) {
        self.namespace = namespace
    }

    func nextSessionID() -> String {
        lock.withLock {
            session += 1
            return "ui-session-\(namespace)-\(session)"
        }
    }

    func nextHandID() -> String {
        lock.withLock {
            hand += 1
            return "ui-hand-\(namespace)-\(hand)"
        }
    }

    func nextBusinessID() -> String {
        lock.withLock {
            business += 1
            return "\(namespace)-\(business)"
        }
    }
}

private final class UITestIdentityProfileSequence {
    private let seed: UInt64
    private var entry = 0

    init(seed: UInt64) {
        self.seed = seed
    }

    func next(humanSeat: SeatID) throws -> [TableSeatProfile] {
        let identities = RobotIdentityCatalog.all
        let start = (Int(seed % UInt64(identities.count)) + entry * 8) % identities.count
        entry += 1
        let robots = (0..<8).map { identities[(start + $0) % identities.count] }
        return try TableSeatProfileFactory.make(humanSeat: humanSeat, robots: robots)
    }
}

struct AppSessionClock: SessionClock {
    var now: Date { Date() }

    var currentDay: LocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let value = String(
            format: "%04d-%02d-%02d",
            components.year ?? 1,
            components.month ?? 1,
            components.day ?? 1
        )
        guard let day = LocalDay(rawValue: value) else {
            preconditionFailure("系统日期无法转换为本地日历日期")
        }
        return day
    }
}

enum CashTableRequestFactory {
    static func validate(
        table: PokerTableSummary,
        buyIn: Int,
        balance: Int
    ) throws {
        guard table.capacity == 9 else { throw PokerSessionError.invalidTable }
        let (minimum, minimumOverflow) = table.bigBlind.multipliedReportingOverflow(
            by: SessionEconomy.minimumBuyInBigBlinds
        )
        let (maximum, maximumOverflow) = table.bigBlind.multipliedReportingOverflow(
            by: SessionEconomy.maximumBuyInBigBlinds
        )
        guard !minimumOverflow, !maximumOverflow else {
            throw PokerSessionError.chipArithmeticOverflow
        }
        guard (minimum...maximum).contains(buyIn) else {
            throw PokerSessionError.invalidBuyIn
        }
        guard buyIn <= balance else {
            throw PokerSessionError.insufficientBalance
        }
    }

    static func make(
        table: PokerTableSummary,
        buyIn: Int,
        balance: Int,
        sessionID: SessionID
    ) throws -> CashTableRequest {
        try validate(table: table, buyIn: buyIn, balance: balance)
        let humanSeat = try SeatID(8)
        let dealer = try SeatID(0)
        let bigBlind = try Chips(table.bigBlind)
        let (botStackValue, overflow) = table.bigBlind.multipliedReportingOverflow(
            by: SessionEconomy.maximumBuyInBigBlinds
        )
        guard !overflow else { throw PokerSessionError.chipArithmeticOverflow }

        var stacks: [SeatID: Chips] = [:]
        for index in 0..<8 {
            stacks[try SeatID(index)] = try Chips(botStackValue)
        }
        stacks[humanSeat] = try Chips(buyIn)

        return CashTableRequest(
            sessionID: sessionID,
            table: try TableID(table.id.uuidString),
            config: try HandConfig(
                smallBlind: try Chips(table.smallBlind),
                bigBlind: bigBlind,
                dealer: dealer
            ),
            humanSeat: humanSeat,
            stacks: stacks
        )
    }
}

enum TableSeatProfileFactory {
    static func make(humanSeat: SeatID) throws -> [TableSeatProfile] {
        var generator = SystemRandomNumberGenerator()
        return try make(humanSeat: humanSeat, using: &generator)
    }

    static func make<R: RandomNumberGenerator>(
        humanSeat: SeatID,
        using generator: inout R
    ) throws -> [TableSeatProfile] {
        let robots = RobotIdentityCatalog.draw(count: 8, using: &generator)
        return try make(humanSeat: humanSeat, robots: robots)
    }

    static func make(
        humanSeat: SeatID,
        robots: [RobotIdentity]
    ) throws -> [TableSeatProfile] {
        guard robots.count == 8,
              Set(robots.map(\.id)).count == 8
        else {
            throw PokerCoordinatorError.missingObservation
        }
        let robotAvatarNames = Set(robots.map(\.avatarAssetName))
        guard let humanAvatarName = RobotIdentityCatalog.all.first(where: {
            !robotAvatarNames.contains($0.avatarAssetName)
        })?.avatarAssetName else {
            throw PokerCoordinatorError.missingObservation
        }
        var robotIndex = 0
        return try (0..<9).map { index in
            let seat = try SeatID(index)
            if seat == humanSeat {
                return try TableSeatProfile(
                    id: seat,
                    displayName: "RiverAce",
                    avatarAssetName: humanAvatarName
                )
            }
            let identity = robots[robotIndex]
            robotIndex += 1
            return try TableSeatProfile(
                id: seat,
                displayName: identity.displayName,
                avatarAssetName: identity.avatarAssetName
            )
        }
    }
}

extension TableRuntimeDependencies {
    static func live(reduceMotion: Bool) -> Self {
        Self(
            nextHandID: { try HandID(UUID().uuidString) },
            nextBusinessID: { purpose in
                try BusinessID("\(purpose):\(UUID().uuidString)")
            },
            nextSeed: { UInt64.random(in: UInt64.min...UInt64.max) },
            sleep: { duration in
                try await ContinuousClock().sleep(for: duration)
            },
            reduceMotion: reduceMotion
        )
    }
}
