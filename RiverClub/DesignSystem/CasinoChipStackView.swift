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

/// 用于牌桌玩家资产、座位筹码和底池的多色赌场筹码堆。
/// 金额仍以完整数字展示，筹码颜色用于增强真实牌桌的视觉层次。
enum CasinoChipPileLayout {
    static let maximumStackHeight = 6

    static func stackHeights(amount: Int, stackCount: Int) -> [Int] {
        guard amount > 0, stackCount > 0 else { return [] }
        let totalChips: Int
        switch amount {
        case ..<100: totalChips = 2
        case ..<500: totalChips = 3
        case ..<1_000: totalChips = 4
        case ..<5_000: totalChips = 7
        case ..<20_000: totalChips = 10
        default: totalChips = 13
        }
        let visibleStacks = min(stackCount, totalChips)
        var heights = Array(repeating: 0, count: visibleStacks)
        for index in 0..<totalChips {
            let stack = index % visibleStacks
            if heights[stack] < maximumStackHeight {
                heights[stack] += 1
            }
        }
        return heights
    }
}

struct CasinoChipPileView: View, @preconcurrency Animatable {
    private var animatedAmount: CGFloat
    let scale: CGFloat
    let showsAmount: Bool
    let stackCount: Int

    var animatableData: CGFloat {
        get { animatedAmount }
        set { animatedAmount = newValue }
    }

    init(
        amount: Int,
        scale: CGFloat = 1,
        showsAmount: Bool = true,
        stackCount: Int = 3
    ) {
        animatedAmount = CGFloat(max(amount, 0))
        self.scale = scale
        self.showsAmount = showsAmount
        self.stackCount = min(max(stackCount, 1), 5)
    }

    private var amount: Int {
        max(Int(animatedAmount.rounded()), 0)
    }

    private var stackHeights: [Int] {
        CasinoChipPileLayout.stackHeights(amount: amount, stackCount: stackCount)
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: -7) {
                ForEach(Array(stackHeights.enumerated()), id: \.offset) { stackIndex, stackHeight in
                    let denomination = denominations[stackIndex]
                    ZStack(alignment: .bottom) {
                        ForEach(0..<stackHeight, id: \.self) { chipIndex in
                            CasinoChipView(denomination: denomination)
                                .offset(y: -CGFloat(chipIndex) * 3)
                                .zIndex(Double(chipIndex))
                        }
                    }
                    .frame(width: 30, height: 38)
                    .zIndex(Double(stackIndex))
                }
            }

            if showsAmount {
                Text(CasinoChipAmountPresentation.text(for: amount))
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(RCTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.48)
                    .allowsTightening(true)
            }
        }
        .scaleEffect(max(scale, 0), anchor: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("多色赌场筹码堆")
        .accessibilityValue("完整金额 \(CasinoChipAmountPresentation.text(for: amount))")
    }

    private var denominations: [CasinoChipDenomination] {
        guard amount > 0 else { return [] }
        if amount >= 20_000 {
            return [.five, .fiveHundred, .twentyFive, .oneHundred, .oneThousand]
        }
        if amount >= 5_000 {
            return [.oneHundred, .twentyFive, .fiveHundred, .five, .oneThousand]
        }
        if amount >= 1_000 {
            return [.twentyFive, .oneHundred, .five, .fiveHundred, .oneThousand]
        }
        if amount >= 100 {
            return [.oneHundred, .twentyFive, .five, .fiveHundred, .one]
        }
        if amount >= 25 {
            return [.twentyFive, .five, .one, .oneHundred, .fiveHundred]
        }
        return [.one, .five, .twentyFive, .oneHundred, .fiveHundred]
    }
}

/// 飞行动画专用的轻量筹码组。
/// 使用单个 Canvas 代替多层视图、文字和阴影，避免四组筹码同时移动时反复布局。
struct CasinoFlyingChipClusterView: View, Equatable {
    let amount: Int
    let clusterIndex: Int

    var body: some View {
        Canvas { context, size in
            let chipDenomination = self.denomination
            let visibleChips = clusterIndex.isMultiple(of: 2) ? 3 : 2
            let chipWidth = min(size.width - 4, 30)
            let chipHeight = min(size.height * 0.38, 10)
            let originX = (size.width - chipWidth) / 2
            let baseY = size.height - chipHeight - 2

            for layer in 0..<visibleChips {
                let y = baseY - CGFloat(layer) * 3.2
                let rect = CGRect(
                    x: originX,
                    y: y,
                    width: chipWidth,
                    height: chipHeight
                )
                let shadow = rect.offsetBy(dx: 0, dy: 1.6)
                context.fill(
                    Path(ellipseIn: shadow),
                    with: .color(.black.opacity(0.42))
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(chipDenomination.color)
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(chipDenomination.edgeColor.opacity(0.92)),
                    lineWidth: 1
                )
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: 4.2, dy: 2)),
                    with: .color(chipDenomination.ringColor),
                    lineWidth: 0.8
                )
            }
        }
        .accessibilityHidden(true)
    }

    private var denomination: CasinoChipDenomination {
        let palette: [CasinoChipDenomination]
        switch amount {
        case 20_000...:
            palette = [.five, .fiveHundred, .twentyFive, .oneHundred]
        case 5_000...:
            palette = [.oneHundred, .twentyFive, .fiveHundred, .five]
        case 1_000...:
            palette = [.twentyFive, .oneHundred, .five, .fiveHundred]
        case 100...:
            palette = [.oneHundred, .twentyFive, .five, .one]
        case 25...:
            palette = [.twentyFive, .five, .one, .oneHundred]
        default:
            palette = [.one, .five, .twentyFive, .oneHundred]
        }
        return palette[clusterIndex % palette.count]
    }
}

/// 牌桌右上角账户余额专用筹码堆。
/// 固定占位并裁切在自身边界内，避免筹码向下覆盖顶部座位手牌。
struct CasinoWalletChipPileView: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            walletStack(.five, count: 4)
                .offset(x: 0, y: -3)
                .zIndex(1)
            walletStack(.fiveHundred, count: 4)
                .offset(x: 17, y: -6)
                .zIndex(2)
            walletStack(.twentyFive, count: 3)
                .offset(x: 34, y: 1)
                .zIndex(4)
        }
        .scaleEffect(0.82, anchor: .bottomLeading)
        .frame(width: 54, height: 40, alignment: .bottomLeading)
        .clipped()
        .accessibilityHidden(true)
    }

    private func walletStack(
        _ denomination: CasinoChipDenomination,
        count: Int
    ) -> some View {
        ZStack(alignment: .bottom) {
            ForEach(0..<count, id: \.self) { index in
                CasinoChipView(denomination: denomination)
                    .offset(y: -CGFloat(index) * 4)
                    .zIndex(Double(index))
            }
        }
        .frame(width: 30, height: 36, alignment: .bottom)
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
