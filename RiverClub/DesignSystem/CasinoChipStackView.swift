import SwiftUI

/// 牌桌内使用的标准赌场筹码面额；不用于大厅账户余额。
enum CasinoChipDenomination: Int, CaseIterable {
    case one = 1
    case five = 5
    case twentyFive = 25
    case oneHundred = 100
    case fiveHundred = 500
    case oneThousand = 1_000

    var color: Color {
        switch self {
        case .one: .white
        case .five: .red
        case .twentyFive: .green
        case .oneHundred: .black
        case .fiveHundred: .purple
        case .oneThousand: .orange
        }
    }

    /// 供测试和设计语义使用的标准颜色名，避免直接比较 `Color` 实例。
    var semanticColorName: String {
        switch self {
        case .one: "white"
        case .five: "red"
        case .twentyFive: "green"
        case .oneHundred: "black"
        case .fiveHundred: "purple"
        case .oneThousand: "orange"
        }
    }

    fileprivate var edgeColor: Color {
        switch self {
        case .one: .black.opacity(0.72)
        case .oneHundred: .white.opacity(0.86)
        default: .white.opacity(0.82)
        }
    }

    fileprivate var ringColor: Color {
        switch self {
        case .one: .black.opacity(0.68)
        case .oneHundred: .white.opacity(0.72)
        default: .black.opacity(0.46)
        }
    }

    fileprivate static let descending = allCases.sorted { $0.rawValue > $1.rawValue }
}

/// 将金额转为从大到小的贪心筹码序列，供视觉展示使用。
enum CasinoChipBreakdown {
    /// 组件支持的最大可见筹码数，用于保证异常输入不会导致巨量分配。
    static let maximumSupportedVisibleChips = 64

    /// 当完整贪心分解超出可见上限时，保留其从最高面额开始的前缀。
    /// 此时返回值仅表示视觉，不承诺其面额和等于 `amount`。
    /// `maximumVisibleChips` 是调用方请求的上限，结果还会受到
    /// `maximumSupportedVisibleChips` 这个公开安全上限的约束。
    static func make(amount: Int, maximumVisibleChips: Int) -> [CasinoChipDenomination] {
        guard amount > 0, maximumVisibleChips > 0 else {
            return []
        }

        let visibleLimit = min(maximumVisibleChips, maximumSupportedVisibleChips)
        var remainder = amount
        var remainingSlots = visibleLimit
        var result: [CasinoChipDenomination] = []

        for denomination in CasinoChipDenomination.descending where remainingSlots > 0 {
            let availableCount = remainder / denomination.rawValue
            guard availableCount > 0 else { continue }

            let visibleCount = min(availableCount, remainingSlots)
            for _ in 0..<visibleCount {
                result.append(denomination)
            }

            remainder -= visibleCount * denomination.rawValue
            remainingSlots -= visibleCount
        }

        return result
    }
}

/// 牌桌筹码金额的固定展示格式；不使用货币符号，也不依赖设备语言区域。
enum CasinoChipAmountPresentation {
    static func text(for amount: Int) -> String {
        var digits = String(amount.magnitude)
        var grouped = ""

        while digits.count > 3 {
            let groupStart = digits.index(digits.endIndex, offsetBy: -3)
            grouped = "," + String(digits[groupStart...]) + grouped
            digits = String(digits[..<groupStart])
        }

        return amount < 0 ? "-\(digits)\(grouped)" : "\(digits)\(grouped)"
    }
}

struct CasinoChipStackView: View {
    let amount: Int
    /// 同时缩放筹码与完整金额文本，并以中心为锚点；调用方需预留缩放后的外框。
    let scale: CGFloat
    private let maximumVisibleChips: Int

    init(amount: Int, scale: CGFloat = 1, maximumVisibleChips: Int = 8) {
        self.amount = amount
        self.scale = scale
        self.maximumVisibleChips = maximumVisibleChips
    }

    private var chips: [CasinoChipDenomination] {
        CasinoChipBreakdown.make(
            amount: amount,
            maximumVisibleChips: maximumVisibleChips
        )
    }

    private var effectiveScale: CGFloat {
        max(scale, 0)
    }

    private var displayAmount: String {
        CasinoChipAmountPresentation.text(for: amount)
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                ForEach(Array(chips.enumerated()), id: \.offset) { index, denomination in
                    CasinoChipView(denomination: denomination)
                        .offset(y: -CGFloat(index) * 3)
                        .zIndex(Double(index))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 30, height: 22 + CGFloat(max(chips.count - 1, 0)) * 3)

            Text(displayAmount)
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(RCTheme.primaryText)
        }
        .scaleEffect(effectiveScale, anchor: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("赌场筹码堆")
        .accessibilityValue("完整金额 \(displayAmount)")
    }
}

private struct CasinoChipView: View {
    let denomination: CasinoChipDenomination

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.46))
                .offset(y: 2.5)

            Ellipse()
                .fill(denomination.color)

            CasinoChipEdgeBlocks(color: denomination.edgeColor)
                .padding(.horizontal, 1.5)
                .padding(.vertical, 1.5)

            Ellipse()
                .stroke(denomination.ringColor, lineWidth: 1.4)
                .padding(2)

            Ellipse()
                .stroke(denomination.edgeColor.opacity(0.9), lineWidth: 0.8)
                .padding(5.2)

            Text("\(denomination.rawValue)")
                .font(.system(size: 5.5, weight: .black, design: .rounded))
                .foregroundStyle(denomination == .one ? Color.black : Color.white)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 30, height: 19)
        .shadow(color: .black.opacity(0.32), radius: 1.5, y: 1)
    }
}

private struct CasinoChipEdgeBlocks: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            Group {
                edgeGroup(horizontal: true)
                    .position(x: width / 2, y: 2.2)
                edgeGroup(horizontal: true)
                    .position(x: width / 2, y: height - 2.2)
                edgeGroup(horizontal: false)
                    .position(x: 2.2, y: height / 2)
                edgeGroup(horizontal: false)
                    .position(x: width - 2.2, y: height / 2)
            }
        }
    }

    @ViewBuilder
    private func edgeGroup(horizontal: Bool) -> some View {
        if horizontal {
            HStack(spacing: 1) {
                Rectangle().fill(color).frame(width: 3, height: 1.5)
                Rectangle().fill(color).frame(width: 3, height: 1.5)
                Rectangle().fill(color).frame(width: 3, height: 1.5)
            }
        } else {
            VStack(spacing: 1) {
                Rectangle().fill(color).frame(width: 1.5, height: 3)
                Rectangle().fill(color).frame(width: 1.5, height: 3)
            }
        }
    }
}
