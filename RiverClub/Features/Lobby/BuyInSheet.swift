import SwiftUI
import PokerSession

struct BuyInRange: Equatable {
    let minimum: Int
    let maximum: Int

    init(bigBlind: Int, balance: Int) {
        minimum = bigBlind * SessionEconomy.minimumBuyInBigBlinds
        maximum = min(
            bigBlind * SessionEconomy.maximumBuyInBigBlinds,
            balance
        )
    }
}

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
    let errorMessage: String?
    let onConfirm: (Int, Bool) -> Void
    let onCancel: () -> Void

    @State private var state: BuyInState

    init(
        table: PokerTableSummary,
        balance: Int,
        errorMessage: String? = nil,
        onConfirm: @escaping (Int, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.table = table
        self.balance = balance
        self.errorMessage = errorMessage
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        let range = BuyInRange(bigBlind: table.bigBlind, balance: balance)
        _state = State(
            initialValue: BuyInState(
                minimum: range.minimum,
                maximum: range.maximum,
                balance: balance
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("确认买入")
                        .font(.title2.weight(.bold))
                    Text("\(table.name) · 无限注德州扑克 · \(table.smallBlind.formatted()) / \(table.bigBlind.formatted())")
                        .font(.subheadline)
                        .foregroundStyle(RCTheme.secondaryText)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                    .buttonStyle(.bordered)
                    .tint(RCTheme.gold)
                    .accessibilityLabel("关闭买入确认")
            }

            Divider().overlay(RCTheme.secondaryText.opacity(0.3))

            HStack {
                Text("买入娱乐筹码")
                Spacer()
                Text(EntertainmentAmountFormatter.string(state.amount))
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
                Text("最低 \(EntertainmentAmountFormatter.string(state.minimum))")
                Spacer()
                Text(
                    "最高 \(EntertainmentAmountFormatter.string(min(state.maximum, state.balance)))"
                )
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(RCTheme.secondaryText)

            Toggle("低于门槛时自动补充娱乐筹码", isOn: $state.autoTopUp)
                .tint(RCTheme.gold)
                .frame(minHeight: 44)

            if state.balance < state.minimum {
                Label(
                    "余额不足：可用 \(EntertainmentAmountFormatter.string(state.balance))，本桌最低买入 \(EntertainmentAmountFormatter.string(state.minimum))。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("buyIn.error")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("buyIn.transactionError")
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
            .frame(minHeight: 44)
            .disabled(!state.canConfirm)
            .accessibilityIdentifier("buyIn.confirm")
        }
        .foregroundStyle(RCTheme.primaryText)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RCTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: RCTheme.corner)
                .stroke(RCTheme.gold.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 24, y: 10)
    }
}
