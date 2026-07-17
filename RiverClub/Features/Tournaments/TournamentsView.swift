import SwiftUI

struct TournamentRegistrationPresentation: Equatable {
    enum Style: Equatable {
        case available
        case registered
    }

    let title: String
    let style: Style
    let isEnabled: Bool

    init(entryChips: Int, isRegistered: Bool) {
        if isRegistered {
            title = "已报名"
            style = .registered
            isEnabled = false
        } else {
            title = entryChips == 0
                ? "免费报名"
                : "报名 · $\(entryChips.formatted())"
            style = .available
            isEnabled = true
        }
    }
}

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
    let balance: Int
    @State private var selectedTab: TournamentTab = .upcoming
    @State private var loadState: LoadableState<[TournamentSummary]> = .loading
    @State private var registeredIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("锦标赛")
                        .font(.title.bold())
                    Text("参加精彩赛事，赢取娱乐筹码奖励。")
                        .font(.subheadline)
                        .foregroundStyle(RCTheme.secondaryText)
                }
                Spacer()
                Button(action: {}) {
                    Image(systemName: "bell")
                        .frame(width: 44, height: 44)
                }
                ChipBalancePill(balance: balance)
            }

            Picker("赛事分类", selection: $selectedTab) {
                ForEach(TournamentTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(height: 38)

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
                GeometryReader { proxy in
                    let columns = Array(
                        repeating: GridItem(.flexible(), spacing: 10),
                        count: 3
                    )
                    LazyVGrid(columns: columns, spacing: 10) {
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
                    .frame(width: proxy.size.width, alignment: .top)
                }
            }
        }
        .padding(6)
        .foregroundStyle(RCTheme.primaryText)
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
        let registration = TournamentRegistrationPresentation(
            entryChips: tournament.entryChips,
            isRegistered: isRegistered
        )
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
            Text("娱乐筹码奖池 $\(tournament.prizePool.formatted())")
                .font(.body.monospacedDigit())

            HStack(spacing: -7) {
                ForEach(RobotIdentityCatalog.preview(for: tournament.id, count: 5)) { identity in
                    RobotAvatarView(
                        imageName: identity.avatarAssetName,
                        fallbackText: identity.displayName,
                        size: 30
                    )
                }
            }

            Spacer()

            Button(registration.title) {
                guard registration.isEnabled else { return }
                onRegister()
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(
                registration.style == .available
                    ? RCTheme.background
                    : RCTheme.primaryText
            )
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                registration.style == .available
                    ? RCTheme.gold
                    : RCTheme.surfaceRaised,
                in: Capsule()
            )
            .buttonStyle(.plain)
            .disabled(!registration.isEnabled)
            .accessibilityIdentifier(
                "tournament.register.\(tournament.id.uuidString)"
            )
        }
        .foregroundStyle(RCTheme.secondaryText)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
        .background(RCTheme.surface.opacity(0.90), in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: RCTheme.corner)
                .stroke(RCTheme.gold.opacity(0.34), lineWidth: 1)
        }
        .accessibilityIdentifier("tournament.\(tournament.id.uuidString)")
    }

    private var kindTitle: String {
        switch tournament.kind {
        case .beginner: "新手免费赛"
        case .classic: "经典赛事"
        case .turbo: "快速赛事"
        }
    }

}
