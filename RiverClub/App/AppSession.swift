import Observation

enum AppRoute: Equatable { case login, lobby, tables, table, tournaments, profile }

extension AppRoute {
    static let sidebarRoutes: [AppRoute] = [.lobby, .tournaments, .tables, .profile]
}

@MainActor @Observable
final class AppSession {
    var route: AppRoute = .login
    var chipBalance = 128_500
    private var tableState = TableSessionState()
    var selectedTable: PokerTableSummary? { tableState.selectedTable }

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
}
