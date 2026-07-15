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

@MainActor @Observable
final class AppSession {
    var route: AppRoute = .login
    @ObservationIgnored let pokerStore: LocalPokerStore
    private(set) var tableCoordinator: CashTableCoordinator?
    private(set) var botSettings: BotSettings
    private(set) var frozenBotSettings: BotSettings?
    private(set) var botSettingsError: String?
    @ObservationIgnored private let botSettingsRepository: any BotSettingsPersisting
    private var tableState = TableSessionState()

    var chipBalance: Int { pokerStore.accountBalance.rawValue }
    var selectedTable: PokerTableSummary? { tableState.selectedTable }

    init(
        pokerStore: LocalPokerStore,
        botSettingsRepository: any BotSettingsPersisting
    ) {
        self.pokerStore = pokerStore
        self.botSettingsRepository = botSettingsRepository
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
            botSettingsRepository: try BotSettingsRepository.applicationSupport()
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
        _ = autoTopUp
        let request = try CashTableRequestFactory.make(table: table, buyIn: buyIn)
        let profiles = try seatProfiles
            ?? TableSeatProfileFactory.make(humanSeat: request.humanSeat)
        try CashTableCoordinator.validateSeatProfiles(
            profiles,
            matching: Array(request.stacks.keys),
            humanSeat: request.humanSeat
        )
        _ = try pokerStore.sitDown(
            request: request,
            businessID: try BusinessID("sit-down:\(request.sessionID.rawValue)")
        )
        let coordinator = try CashTableCoordinator(
            store: pokerStore,
            humanSeat: request.humanSeat,
            seatProfiles: profiles,
            dependencies: TableRuntimeDependencies.live(reduceMotion: reduceMotion)
        )
        tableCoordinator = coordinator
        tableState.enter(table)
        route = .table
    }

    func leaveTable(returningTo route: AppRoute) {
        tableState.leave()
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
    static func make(
        table: PokerTableSummary,
        buyIn: Int
    ) throws -> CashTableRequest {
        guard table.capacity == 9 else { throw PokerSessionError.invalidTable }
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
            sessionID: try SessionID(UUID().uuidString),
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

private extension TableRuntimeDependencies {
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
