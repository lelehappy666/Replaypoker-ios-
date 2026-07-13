import Observation

enum AppRoute: Equatable { case login, lobby, tables, table, tournaments, profile }

extension AppRoute {
    static let sidebarRoutes: [AppRoute] = [.lobby, .tournaments, .tables, .profile]
}

@MainActor @Observable
final class AppSession {
    var route: AppRoute = .login
    var chipBalance = 128_500
    func continueAsGuest() { route = .lobby }
    func logout() { route = .login }
    func open(_ route: AppRoute) { self.route = route }
}
