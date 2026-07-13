protocol PokerRepository: Sendable {
    func tables() async throws -> [PokerTableSummary]
    func featuredTable() async throws -> PokerTableSummary
    func seats() async throws -> [PokerSeat]
    func tournaments() async throws -> [TournamentSummary]
    func profile() async throws -> ProfileSummary
}
