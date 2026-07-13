import SwiftUI

enum TournamentTab: String, CaseIterable, Identifiable, Sendable {
    case upcoming = "即将开始"
    case registered = "已报名"
    case active = "进行中"
    case finished = "已结束"

    var id: Self { self }

    func filtered(
        _ tournaments: [TournamentSummary],
        now: Date = .now,
        registeredIDs: Set<UUID> = []
    ) -> [TournamentSummary] {
        switch self {
        case .upcoming:
            tournaments.filter { $0.startTime > now }
        case .registered:
            tournaments.filter { registeredIDs.contains($0.id) }
        case .active:
            tournaments.filter { $0.startTime <= now && $0.endTime > now }
        case .finished:
            tournaments.filter { $0.endTime <= now }
        }
    }

    var identifier: String {
        switch self {
        case .upcoming: "upcoming"
        case .registered: "registered"
        case .active: "active"
        case .finished: "finished"
        }
    }
}

struct TournamentsView: View {
    let repository: any PokerRepository
    @State private var selectedTab: TournamentTab = .upcoming
    @State private var loadState: LoadableState<[TournamentSummary]> = .loading
    @State private var registeredIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("锦标赛")
                .font(.largeTitle.bold())
                .foregroundStyle(RCTheme.primaryText)

            HStack(spacing: 8) {
                ForEach(TournamentTab.allCases) { tab in
                    Button(tab.rawValue) { selectedTab = tab }
                        .buttonStyle(.bordered)
                        .tint(selectedTab == tab ? RCTheme.gold : RCTheme.secondaryText)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("tournaments.tab.\(tab.identifier)")
                }
            }

            LoadableContent(
                state: loadState,
                hasActiveFilters: selectedTab != .upcoming,
                isEmpty: {
                    selectedTab.filtered($0, registeredIDs: registeredIDs).isEmpty
                },
                emptyTitle: "暂无赛事",
                emptyDescription: "此分类暂时没有赛事。",
                onRetry: { Task { await loadTournaments() } },
                onClearFilters: { selectedTab = .upcoming }
            ) { tournaments in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(
                            selectedTab.filtered(tournaments, registeredIDs: registeredIDs)
                        ) { tournament in
                            TournamentCard(
                                tournament: tournament,
                                isRegistered: registeredIDs.contains(tournament.id),
                                onRegister: { registeredIDs.insert(tournament.id) }
                            )
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(RCTheme.background)
        .task { await loadTournaments() }
    }

    @MainActor
    private func loadTournaments() async {
        let cached = loadState.content
        if cached == nil { loadState = .loading }
        do {
            loadState = .loaded(try await repository.tournaments())
        } catch {
            loadState = cached == nil
                ? .failed(message: "请检查网络连接后重试。")
                : .offline(cached: cached)
        }
    }
}

private struct TournamentCard: View {
    let tournament: TournamentSummary
    let isRegistered: Bool
    let onRegister: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kindTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RCTheme.gold)
            Text(tournament.name)
                .font(.title3.bold())
                .foregroundStyle(RCTheme.primaryText)
            Label {
                Text(tournament.startTime, style: .time)
            } icon: {
                Image(systemName: "clock")
            }
            Text("报名 \(tournament.registered) / \(tournament.capacity)")
                .monospacedDigit()
            Text("娱乐筹码奖池 \(tournament.prizePool.formatted())")
                .font(.body.monospacedDigit())

            Spacer()

            Button(buttonTitle) {
                guard !isRegistered else { return }
                onRegister()
            }
            .buttonStyle(.borderedProminent)
            .tint(RCTheme.gold)
            .frame(minHeight: 44)
            .disabled(isRegistered)
        }
        .foregroundStyle(RCTheme.secondaryText)
        .padding(18)
        .frame(width: 250, height: 230, alignment: .leading)
        .background(RCTheme.surface, in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .accessibilityIdentifier("tournament.\(tournament.id.uuidString)")
    }

    private var kindTitle: String {
        switch tournament.kind {
        case .beginner: "新手免费赛"
        case .classic: "经典赛事"
        case .turbo: "快速赛事"
        }
    }

    private var buttonTitle: String {
        if isRegistered { return "已报名" }
        if tournament.entryChips == 0 { return "免费报名" }
        return "报名 · \(tournament.entryChips.formatted()) 筹码"
    }
}
