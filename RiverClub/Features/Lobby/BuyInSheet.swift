import SwiftUI

struct BuyInState: Equatable {
    let minimum: Int
    let maximum: Int
    let balance: Int
    var amount: Int
    var autoTopUp = false

    init(minimum: Int, maximum: Int, balance: Int) {
        self.minimum = minimum
        self.maximum = maximum
        self.balance = balance
        amount = min(minimum, min(maximum, balance))
    }

    var canConfirm: Bool {
        balance >= minimum && amount >= minimum && amount <= min(maximum, balance)
    }

    mutating func normalize() {
        let upperBound = min(maximum, balance)
        amount = upperBound < minimum
            ? upperBound
            : min(max(amount, minimum), upperBound)
    }
}

struct BuyInSheet: View {
    let table: PokerTableSummary
    let balance: Int
    let onConfirm: (Int, Bool) -> Void
    let onCancel: () -> Void

    @State private var state: BuyInState

    init(
        table: PokerTableSummary,
        balance: Int,
        onConfirm: @escaping (Int, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.table = table
        self.balance = balance
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _state = State(
            initialValue: BuyInState(
                minimum: table.bigBlind * 10,
                maximum: table.bigBlind * 50,
                balance: balance
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("确认买入")
                        .font(.title2.weight(.bold))
                    Text("\(table.name) · 无限注德州扑克 · \(table.smallBlind.formatted()) / \(table.bigBlind.formatted())")
                        .font(.subheadline)
                        .foregroundStyle(RCTheme.secondaryText)
                }
                Spacer()
                Button("返回", action: onCancel)
                    .buttonStyle(.bordered)
                    .tint(RCTheme.gold)
            }

            Divider().overlay(RCTheme.secondaryText.opacity(0.3))

            HStack {
                Text("买入娱乐筹码")
                Spacer()
                Text(state.amount.formatted())
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(RCTheme.gold)
            }

            Slider(
                value: Binding(
                    get: { Double(state.amount) },
                    set: {
                        state.amount = Int($0.rounded())
                        state.normalize()
                    }
                ),
                in: Double(state.minimum)...Double(max(state.minimum, min(state.maximum, state.balance))),
                step: Double(max(table.bigBlind, 1))
            )
            .tint(RCTheme.gold)
            .disabled(state.balance < state.minimum)
            .accessibilityIdentifier("buyIn.slider")

            HStack {
                Text("最低 \(state.minimum.formatted())")
                Spacer()
                Text("最高 \(min(state.maximum, state.balance).formatted())")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(RCTheme.secondaryText)

            Toggle("低于门槛时自动补充娱乐筹码", isOn: $state.autoTopUp)
                .tint(RCTheme.gold)

            if state.balance < state.minimum {
                Label(
                    "余额不足：可用 \(state.balance.formatted())，本桌最低买入 \(state.minimum.formatted())。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("buyIn.error")
            }

            Button {
                guard state.canConfirm else { return }
                onConfirm(state.amount, state.autoTopUp)
            } label: {
                Text("确认买入并入座")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(RCTheme.gold)
            .foregroundStyle(RCTheme.background)
            .controlSize(.large)
            .disabled(!state.canConfirm)
            .accessibilityIdentifier("buyIn.confirm")
        }
        .foregroundStyle(RCTheme.primaryText)
        .padding(24)
        .frame(minWidth: 480, idealWidth: 540)
        .background(RCTheme.surfaceRaised)
        .presentationBackground(RCTheme.surfaceRaised)
        .presentationCornerRadius(RCTheme.corner)
    }
}
