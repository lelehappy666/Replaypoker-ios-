# 任务 4：真实多面额赌场筹码组件报告

## 实现

- 新增 `RiverClub/DesignSystem/CasinoChipStackView.swift`，提供 `CasinoChipDenomination`、`CasinoChipBreakdown.make(amount:maximumVisibleChips:)` 与 `CasinoChipStackView(amount:scale:)`。
- 面额和颜色固定为：白色 1、红色 5、绿色 25、黑色 100、紫色 500、橙色 1000。
- 单枚筹码包含椭圆主体、向下偏移的侧面厚度、内外双圆环、顶部/底部/左侧/右侧四组边缘色块。白筹码使用深色轮廓，黑筹码使用浅色轮廓，均保持边界对比。
- 堆叠采用每枚 3pt 的纵向偏移；`scale` 通过以底部为锚点的 `scaleEffect` 生效；所有单枚筹码对无障碍隐藏，堆叠统一提供完整金额的无障碍值。
- 未修改 `PokerTableView`、`PokerSeatView`、大厅金额格式或金额/下注/结算计算。

## 算法与压缩策略

- 按 1000、500、100、25、5、1 进行确定性贪心分解。
- 金额大于 0 且完整分解未触及上限时，返回的筹码面额和精确等于金额。
- 当达到上限时，停止生成并保留“最高面额优先”的贪心前缀；这仅是视觉压缩，返回筹码的面额和不再宣称等于原金额。
- 组件通过无障碍值 `完整金额 <amount>` 携带原始完整金额，避免视觉压缩丢失语义。
- 除调用方上限外，另设 64 枚内部安全上限。它使 `amount == Int.max` 或 `maximumVisibleChips == Int.max` 始终有界，不会巨量分配或无限循环；结果仍不超过调用方的上限。

## TDD 与测试

- RED：先新增 `CasinoChipStackTests.swift` 和工程引用，再运行 `xcodebuild build-for-testing`；因 `CasinoChipStackView.swift` 尚不存在，构建按预期报“Build input file cannot be found”。
- GREEN：实现组件后，运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/replaypoker-task4-green CODE_SIGNING_ALLOWED=NO`，退出成功并显示 `TEST BUILD SUCCEEDED`。
- 测试覆盖：600 精确为 500+100、大底池计数上限、所有标准面额、非正金额/上限、可容纳的非标准金额精确分解、压缩的最高面额前缀、`Int.max` 与内部安全上限。

## 边界与自查风险

- `amount <= 0` 或 `maximumVisibleChips <= 0` 返回空数组；分解中仅使用安全的除法、受上限约束的乘法和有界循环。
- 项目已通过测试源码编译；当前环境的模拟器测试执行服务不稳定，因此遵循任务约束，只使用可计数的 `build-for-testing`，未重复排查或声称已在模拟器运行。
- 视觉效果已在源码层自查；尚未进行真机或截图级视觉验收，后续牌桌接入任务应在实际横屏尺寸复核筹码缩放与遮挡。
