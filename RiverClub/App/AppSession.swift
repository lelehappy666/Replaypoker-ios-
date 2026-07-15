import Foundation
import Observation
import PokerBot
import PokerCoordinator
import PokerCore
import PokerSession

enum AppRoute: Equatable { case login, lobby, tables, table, tournaments, profile }

extension AppRoute {
    static let sidebarRoutes: [AppRoute] = [.lobby, .tournaments, .tables, .profile]
}

enum AppSessionError: Error, Equatable {
    case conflictingCashTableAttempt
}

@MainActor
struct AppSessionDependencies {
    let nextSessionID: () throws -> SessionID
    let nextBusinessID: (_ purpose: String) throws -> BusinessID
    let makeRuntimeDependencies: (_ reduceMotion: Bool) -> TableRuntimeDependencies
    let makeCoordinator: (
        _ store: LocalPokerStore,
        _ humanSeat: SeatID,
        _ profiles: [TableSeatProfile],
        _ runtime: TableRuntimeDependencies
    ) throws -> CashTableCoordinator

    static var live: Self {
        Self(
            nextSessionID: { try SessionID(UUID().uuidString) },
            nextBusinessID: { purpose in
                try BusinessID("\(purpose):\(UUID().uuidString)")
            },
            makeRuntimeDependencies: TableRuntimeDependencies.live,
            makeCoordinator: { store, humanSeat, profiles, runtime in
                try CashTableCoordinator(
                    store: store,
                    humanSeat: humanSeat,
                    seatProfiles: profiles,
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

@MainActor @Observable
final class AppSession {
    var route: AppRoute = .login
    @ObservationIgnored let pokerStore: LocalPokerStore
    private(set) var tableCoordinator: CashTableCoordinator?
    private(set) var botSettings: BotSettings
    private(set) var frozenBotSettings: BotSettings?
    private(set) var botSettingsError: String?
    private(set) var tableStartupError: String?
    @ObservationIgnored private let botSettingsRepository: any BotSettingsPersisting
    @ObservationIgnored private let dependencies: AppSessionDependencies
    private var tableState = TableSessionState()
    private var cashTableJoinAttempt: CashTableJoinAttempt?
    private var isStartingOrResumingTableHand = false

    var chipBalance: Int { pokerStore.accountBalance.rawValue }
    var selectedTable: PokerTableSummary? { tableState.selectedTable }

    init(
        pokerStore: LocalPokerStore,
        botSettingsRepository: any BotSettingsPersisting,
        dependencies: AppSessionDependencies = .live
    ) {
        self.pokerStore = pokerStore
        self.botSettingsRepository = botSettingsRepository
        self.dependencies = dependencies
        do {
            botSettings = try botSettingsRepository.load()
            botSettingsError = nil
        } catch {
            botSettings = .recommended
            botSettingsError = "机器人设置读取失败，请检查设置文件或恢复推荐设置。"
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
        let store = try LocalPokerStore.open(
            directory: sessionDirectory,
            clock: AppSessionClock()
        )
        return AppSession(
            pokerStore: store,
            botSettingsRepository: try BotSettingsRepository.applicationSupport(),
            dependencies: .live
        )
    }

    static func uiTestingImmediate() throws -> AppSession {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "RiverClub-Immediate-UITests",
            isDirectory: true
        )
        try? fileManager.removeItem(at: directory)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let ids = UITestIDSequence()
        let store = try LocalPokerStore.open(
            directory: directory,
            clock: AppSessionClock()
        )
        return AppSession(
            pokerStore: store,
            botSettingsRepository: MemoryBotSettingsRepository(initial: .recommended),
            dependencies: AppSessionDependencies(
                nextSessionID: { try SessionID("ui-session") },
                nextBusinessID: { purpose in
                    try BusinessID("ui:\(purpose)")
                },
                makeRuntimeDependencies: { _ in
                    TableRuntimeDependencies(
                        nextHandID: { try HandID(ids.nextHandID()) },
                        nextBusinessID: { purpose in
                            try BusinessID("ui:\(purpose):\(ids.nextBusinessID())")
                        },
                        nextSeed: { 37 },
                        sleep: { duration in
                            guard duration > .zero else { return }
                            try await ContinuousClock().sleep(for: .seconds(300))
                        },
                        reduceMotion: true
                    )
                },
                makeCoordinator: { store, humanSeat, profiles, runtime in
                    try CashTableCoordinator(
                        store: store,
                        humanSeat: humanSeat,
                        seatProfiles: profiles,
                        dependencies: runtime
                    )
                }
            )
        )
    }

    func continueAsGuest() { route = .lobby }
    func logout() { route = .login }
    func open(_ route: AppRoute) { self.route = route }

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
                ?? TableSeatProfileFactory.make(humanSeat: request.humanSeat)
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
        let coordinator = try dependencies.makeCoordinator(
            pokerStore,
            attempt.request.humanSeat,
            attempt.profiles,
            dependencies.makeRuntimeDependencies(reduceMotion)
        )
        tableCoordinator = coordinator
        tableState.enter(table)
        tableStartupError = nil
        route = .table
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

    func leaveTable(returningTo route: AppRoute) {
        tableState.leave()
        tableStartupError = nil
        self.route = route
    }

    func saveBotSettings(_ settings: BotSettings) throws {
        try botSettingsRepository.save(settings)
        botSettings = settings
        botSettingsError = nil
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
    private var hand = 0
    private var business = 0

    func nextHandID() -> String {
        lock.withLock {
            hand += 1
            return "ui-hand-\(hand)"
        }
    }

    func nextBusinessID() -> Int {
        lock.withLock {
            business += 1
            return business
        }
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
    private static let botNames = [
        "林墨", "青屿", "空山", "云雀", "晨星", "海盐", "玖未", "深野",
    ]

    static func make(humanSeat: SeatID) throws -> [TableSeatProfile] {
        var botIndex = 0
        return try (0..<9).map { index in
            let seat = try SeatID(index)
            if seat == humanSeat {
                return try TableSeatProfile(id: seat, displayName: "RiverAce")
            }
            defer { botIndex += 1 }
            return try TableSeatProfile(id: seat, displayName: botNames[botIndex])
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
