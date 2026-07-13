import SwiftUI

struct ProfileView: View {
    let repository: any PokerRepository
    @State private var loadState: LoadableState<ProfileSummary> = .loading
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("个人中心")
                .font(.largeTitle.bold())
                .foregroundStyle(RCTheme.primaryText)

            LoadableContent(
                state: loadState,
                hasActiveFilters: false,
                isEmpty: { _ in false },
                emptyTitle: "暂无个人资料",
                emptyDescription: "请稍后重试。",
                onRetry: { Task { await loadProfile() } },
                onClearFilters: {}
            ) { profile in
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 18) {
                        Circle()
                            .fill(RCTheme.gold)
                            .frame(width: 72, height: 72)
                            .overlay {
                                Text(String(profile.nickname.prefix(1)))
                                    .font(.title.bold())
                                    .foregroundStyle(RCTheme.background)
                            }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(profile.nickname)
                                .font(.title2.bold())
                                .accessibilityIdentifier("profile.nickname")
                            Text("白银会员 · 等级 \(profile.level)")
                                .foregroundStyle(RCTheme.secondaryText)
                            ProgressView(value: min(Double(profile.level) / 30, 1))
                                .tint(RCTheme.gold)
                                .frame(width: 220)
                        }
                        Spacer()
                    }

                    HStack(spacing: 14) {
                        ProfileStatCard(title: "总手数", value: profile.handsPlayed.formatted())
                        ProfileStatCard(
                            title: "入池率",
                            value: profile.voluntaryPutInPot.formatted(.percent.precision(.fractionLength(1)))
                        )
                        ProfileStatCard(title: "赛事奖励", value: profile.tournamentAwards.formatted())
                    }

                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                        profileLink("牌局记录", icon: "clock.arrow.circlepath")
                        profileLink("成就徽章", icon: "medal")
                        profileLink("账户与安全", icon: "lock.shield")
                        profileLink("声音与震动", icon: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("profile.settings")

                    if let statusMessage {
                        Label(statusMessage, systemImage: "info.circle")
                            .foregroundStyle(RCTheme.secondaryText)
                            .accessibilityIdentifier("profile.unavailable")
                    }
                }
            }
        }
        .padding(24)
        .foregroundStyle(RCTheme.primaryText)
        .background(RCTheme.background)
        .task { await loadProfile() }
    }

    private func profileLink(_ title: String, icon: String) -> some View {
        Button { statusMessage = "\(title)暂未开放" } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    @MainActor
    private func loadProfile() async {
        let cached = loadState.content
        if cached == nil { loadState = .loading }
        do {
            loadState = .loaded(try await repository.profile())
        } catch {
            loadState = cached == nil
                ? .failed(message: "无法加载个人资料，请重试。")
                : .offline(cached: cached)
        }
    }
}

private struct ProfileStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(RCTheme.gold)
            Text(title)
                .font(.caption)
                .foregroundStyle(RCTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 86)
        .background(RCTheme.surface, in: RoundedRectangle(cornerRadius: RCTheme.corner))
    }
}
