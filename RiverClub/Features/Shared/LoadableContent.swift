import SwiftUI

enum LoadableState<Value> {
    case loading
    case loaded(Value)
    case offline(cached: Value?)
    case failed(message: String)

    var content: Value? {
        switch self {
        case let .loaded(value): value
        case let .offline(cached): cached
        case .loading, .failed: nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }

    var showsOfflineBanner: Bool {
        if case let .offline(cached) = self { cached != nil } else { false }
    }

    var allowsRetry: Bool {
        switch self {
        case .offline, .failed: true
        case .loading, .loaded: false
        }
    }

    var failureMessage: String? {
        if case let .failed(message) = self { message } else { nil }
    }

    func showsClearFilters(hasActiveFilters: Bool, filteredIsEmpty: Bool) -> Bool {
        content != nil && hasActiveFilters && filteredIsEmpty
    }
}

struct LoadableContent<Value, Content: View>: View {
    let state: LoadableState<Value>
    let hasActiveFilters: Bool
    let isEmpty: (Value) -> Bool
    let emptyTitle: String
    let emptyDescription: String
    let onRetry: () -> Void
    let onClearFilters: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        VStack(spacing: 12) {
            if state.showsOfflineBanner {
                offlineBanner
            }

            switch state {
            case .loading:
                LoadableSkeleton()
            case let .loaded(value):
                loaded(value)
            case let .offline(cached):
                if let cached {
                    loaded(cached)
                } else {
                    recovery(message: "当前处于离线状态，请重试。")
                }
            case let .failed(message):
                recovery(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func loaded(_ value: Value) -> some View {
        if isEmpty(value) {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(emptyDescription)
            } actions: {
                if state.showsClearFilters(
                    hasActiveFilters: hasActiveFilters,
                    filteredIsEmpty: true
                ) {
                    Button("清除筛选", action: onClearFilters)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("loadable.clearFilters")
                }
            }
            .foregroundStyle(RCTheme.primaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content(value)
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("网络已断开，正在显示上次加载的内容。")
            Spacer()
            Button("重试", action: onRetry)
                .frame(minHeight: 44)
        }
        .font(.subheadline)
        .foregroundStyle(RCTheme.primaryText)
        .padding(.horizontal, 14)
        .background(RCTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .accessibilityIdentifier("loadable.offline")
    }

    private func recovery(message: String) -> some View {
        VStack(spacing: 12) {
            Label("暂时无法加载", systemImage: "wifi.exclamationmark")
                .font(.headline)
            Text(message)
                .foregroundStyle(RCTheme.secondaryText)
            Button("重试", action: onRetry)
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("loadable.retry")
        }
        .foregroundStyle(RCTheme.primaryText)
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RCTheme.surface, in: RoundedRectangle(cornerRadius: RCTheme.corner))
    }
}

private struct LoadableSkeleton: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: RCTheme.corner)
                    .fill(RCTheme.surface)
                    .frame(height: 72)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载")
    }
}
