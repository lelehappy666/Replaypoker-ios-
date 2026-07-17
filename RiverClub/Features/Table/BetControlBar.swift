import PokerCoordinator
import PokerCore
import SwiftUI

struct BetControlPreset: Equatable {
    let title: String
    let amount: Int
}

enum BetControlPresentation {
    static func title(for middle: TableMiddleAction) -> String {
        switch middle {
        case .check:
            return "过牌"
        case let .call(amount):
            return "跟注 \(amount.rawValue.formatted())"
        }
    }

    static func title(
        for aggressive: TableAggressiveAction,
        amount: Chips
    ) -> String {
        let values = values(for: aggressive)
        if values.canAllIn, amount == values.maximum {
            return "全下"
        }
        let verb: String
        switch aggressive {
        case .bet:
            verb = "下注"
        case .raise:
            verb = "加注"
        }
        return "\(verb) \(amount.rawValue.formatted())"
    }

    static func range(for aggressive: TableAggressiveAction) -> ClosedRange<Int> {
        let values = values(for: aggressive)
        return values.minimum.rawValue...values.maximum.rawValue
    }

    static func clampedAmount(
        _ amount: Int,
        for aggressive: TableAggressiveAction
    ) -> Int {
        let range = range(for: aggressive)
        return min(max(amount, range.lowerBound), range.upperBound)
    }

    static func presets(
        for aggressive: TableAggressiveAction,
        pot: Chips
    ) -> [BetControlPreset] {
        let range = range(for: aggressive)
        let candidates = [
            ("半池", pot.rawValue / 2),
            ("四分之三池", threeQuarterPot(pot.rawValue)),
        ]
        var seen: Set<Int> = []
        return candidates.compactMap { title, rawAmount in
            guard let rawAmount else { return nil }
            let clipped = min(max(rawAmount, range.lowerBound), range.upperBound)
            guard clipped != range.lowerBound, seen.insert(clipped).inserted else {
                return nil
            }
            return BetControlPreset(title: title, amount: clipped)
        }
    }

    private static func values(
        for aggressive: TableAggressiveAction
    ) -> (minimum: Chips, maximum: Chips, canAllIn: Bool) {
        switch aggressive {
        case let .bet(minimum, maximum, canAllIn),
             let .raise(minimum, maximum, canAllIn):
            return (minimum, maximum, canAllIn)
        }
    }

    private static func threeQuarterPot(_ pot: Int) -> Int? {
        let (tripled, overflow) = pot.multipliedReportingOverflow(by: 3)
        return overflow ? nil : tripled / 4
    }
}

struct BetControlBar: View {
    let controls: TableActionControls
    let pot: Chips
    let onIntent: (TableIntent) -> Void

    @State private var aggressiveAmount: Int

    init(
        controls: TableActionControls,
        pot: Chips,
        onIntent: @escaping (TableIntent) -> Void
    ) {
        self.controls = controls
        self.pot = pot
        self.onIntent = onIntent
        _aggressiveAmount = State(
            initialValue: controls.aggressive.map {
                BetControlPresentation.range(for: $0).lowerBound
            } ?? 0
        )
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let aggressive = controls.aggressive {
                aggressivePicker(for: aggressive)
            }

            HStack(spacing: 8) {
                if controls.canFold {
                    actionButton(
                        "弃牌",
                        tint: RCTheme.surfaceRaised,
                        foreground: RCTheme.primaryText,
                        identifier: "action.fold"
                    ) { onIntent(.fold) }
                }
                if let middle = controls.middle {
                    actionButton(
                        BetControlPresentation.title(for: middle),
                        tint: RCTheme.surfaceRaised,
                        foreground: RCTheme.primaryText,
                        identifier: "action.middle"
                    ) { onIntent(.middle) }
                }
                if let aggressive = controls.aggressive,
                   let amount = Chips(
                       rawValue: BetControlPresentation.clampedAmount(
                           aggressiveAmount,
                           for: aggressive
                       )
                   ) {
                    actionButton(
                        BetControlPresentation.title(
                            for: aggressive,
                            amount: amount
                        ),
                        tint: RCTheme.gold,
                        foreground: RCTheme.background,
                        identifier: "action.aggressive"
                    ) { onIntent(.aggressive(amount: amount)) }
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: RCTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: RCTheme.corner)
                .stroke(RCTheme.gold.opacity(0.20), lineWidth: 1)
        }
        .onChange(of: controls) { _, newControls in
            guard let aggressive = newControls.aggressive else { return }
            aggressiveAmount = BetControlPresentation.range(for: aggressive).lowerBound
        }
    }

    private func aggressivePicker(
        for aggressive: TableAggressiveAction
    ) -> some View {
        let range = BetControlPresentation.range(for: aggressive)
        let displayedAmount = BetControlPresentation.clampedAmount(
            aggressiveAmount,
            for: aggressive
        )
        return VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                ForEach(
                    BetControlPresentation.presets(for: aggressive, pot: pot),
                    id: \.amount
                ) { preset in
                    presetButton(preset)
                }
                Text(displayedAmount.formatted())
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(RCTheme.gold)
                    .frame(minWidth: 52, alignment: .trailing)
            }

            Slider(
                value: Binding(
                    get: { Double(displayedAmount) },
                    set: { aggressiveAmount = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(RCTheme.gold)
            .frame(width: 240)
            .accessibilityLabel("下注或加注娱乐筹码")
            .accessibilityIdentifier("action.aggressiveSlider")
        }
    }

    private func presetButton(_ preset: BetControlPreset) -> some View {
        Button(preset.title) { aggressiveAmount = preset.amount }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(RCTheme.gold)
            .frame(minHeight: 44)
            .accessibilityIdentifier("action.preset.\(preset.amount)")
    }

    private func actionButton(
        _ title: String,
        tint: Color,
        foreground: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 42)
            .accessibilityIdentifier(identifier)
    }
}
