import Observation
import PokerBot

enum AppRoute: Equatable { case login, lobby, tables, table, tournaments, profile }

extension AppRoute {
    static let sidebarRoutes: [AppRoute] = [.lobby, .tournaments, .tables, .profile]
}

@MainActor @Observable
final class AppSession {
    var route: AppRoute = .login
    var chipBalance = 128_500
    private(set) var botSettings: BotSettings
    private(set) var frozenBotSettings: BotSettings?
    private(set) var botSettingsError: String?
    @ObservationIgnored private let botSettingsRepository: any BotSettingsPersisting
    private var tableState = TableSessionState()
    var selectedTable: PokerTableSummary? { tableState.selectedTable }

    init(botSettingsRepository: (any BotSettingsPersisting)? = nil) {
        if let repository = botSettingsRepository {
            self.botSettingsRepository = repository
            do {
                botSettings = try repository.load()
                botSettingsError = nil
            } catch {
                botSettings = .recommended
                botSettingsError = "机器人设置读取失败，请检查设置文件或恢复推荐设置。"
            }
        } else {
            let repository: any BotSettingsPersisting
            do {
                repository = try BotSettingsRepository.applicationSupport()
            } catch {
                repository = MemoryBotSettingsRepository(initial: .recommended)
            }
            self.botSettingsRepository = repository
            do {
                botSettings = try repository.load()
                botSettingsError = nil
            } catch {
                botSettings = .recommended
                botSettingsError = "机器人设置读取失败，请检查设置文件或恢复推荐设置。"
            }
        }
    }

    func continueAsGuest() { route = .lobby }
    func logout() { route = .login }
    func open(_ route: AppRoute) { self.route = route }

    func enterTable(_ table: PokerTableSummary) {
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
