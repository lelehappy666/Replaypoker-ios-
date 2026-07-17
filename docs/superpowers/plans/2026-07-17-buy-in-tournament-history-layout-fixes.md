# River Club 买入、锦标赛按钮与存档布局修复实施计划

> **面向代理开发者：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项实施。所有步骤使用复选框跟踪。

**目标：** 自动安全结算启动时遗留的普通桌会话，让新买入恢复可用，同时提高锦标赛按钮对比度并保证存档列表右侧信息不被裁切。

**架构：** 在 `AppSession` 中复用现有 `CashTableCoordinator.leaveTable` 完成遗留会话的存档、结算和兑现，并由根视图启动任务及展示失败重试状态。锦标赛按钮使用纯展示模型明确颜色语义；存档页使用顶层实际容器宽度统一计算筛选栏和列表行指标。

**技术栈：** Swift 6、SwiftUI、Observation、Swift Testing/XCTest、PokerCore、PokerSession、PokerCoordinator、XCUITest。

## 全局约束

- 目标设备为 iPhone 16 Pro Max，全程横屏。
- 所有面向用户的说明、规格、计划和交付说明使用中文。
- 所有 Git 与 GitHub 提交信息使用中文。
- 自动结算必须走现有安全离桌流程，不直接删除会话或直接改余额。
- 新增行为严格遵循测试先行：先看到目标测试正确失败，再写最小实现。
- 不修改锦标赛报名业务、存档格式、整体主题或牌桌玩法。

---

### 任务 1：启动时安全结算遗留普通桌

**文件：**

- 修改：`RiverClub/App/AppSession.swift`
- 修改：`RiverClub/App/AppRootView.swift`
- 修改：`RiverClubTests/CashTableEntryTests.swift`

**接口：**

- 消费：`LocalPokerStore.cashSession`、`CashTableCoordinator.leaveTable(settlementID:cashOutID:)`、`TableSeatProfileFactory.make(humanSeat:)`。
- 产出：`AppSession.settleAbandonedCashSessionIfNeeded() async`、`AppSession.retryAbandonedCashSessionSettlement() async`、`AppSession.isSettlingAbandonedCashSession`、`AppSession.abandonedCashSessionError`、`AppSession.hasUnsettledCashSession`。

- [ ] **步骤 1：编写遗留会话自动结算失败测试**

在 `CashTableEntryTests` 创建已经买入并开始一手牌的存储，再用同一存储构造新的 `AppSession`，验证调用启动结算后：活动会话为空、余额等于结算前账户余额加玩家桌上剩余筹码、不会重复兑现。再注入第一次失败的协调器，验证错误可见、会话保留、重试复用同一组业务编号。

```swift
@MainActor
func testLaunchSettlementClosesAbandonedSessionAndReturnsStack() async throws {
    let fixture = try AppSessionFixture()
    try fixture.session.joinCashTable(
        fixture.table,
        buyIn: 16_000,
        autoTopUp: false,
        reduceMotion: true
    )
    let expected = fixture.session.chipBalance
        + (fixture.store.cashSession?.seats.first {
            $0.id == fixture.store.cashSession?.humanSeat
        }?.stack.rawValue ?? 0)

    await fixture.session.settleAbandonedCashSessionIfNeeded()

    XCTAssertNil(fixture.store.cashSession)
    XCTAssertEqual(fixture.session.chipBalance, expected)
    XCTAssertNil(fixture.session.abandonedCashSessionError)
}
```

- [ ] **步骤 2：运行测试并确认正确失败**

运行：

```bash
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:RiverClubTests/CashTableEntryTests
```

预期：编译失败，提示 `AppSession` 尚无 `settleAbandonedCashSessionIfNeeded` 或相关状态。

- [ ] **步骤 3：实现最小遗留会话结算状态机**

在 `AppSession` 中增加一次结算尝试对象，保存协调器、结算编号和兑现编号。方法需满足：无活动会话立即返回；同一时间只运行一次；从持久化会话的人类座位重建默认展示资料；调用现有协调器安全离桌；成功后清除尝试和错误；失败后保留尝试并公开中文错误。

```swift
private struct AbandonedCashSessionSettlementAttempt {
    let coordinator: CashTableCoordinator
    let settlementID: BusinessID
    let cashOutID: BusinessID
}

func settleAbandonedCashSessionIfNeeded() async {
    guard pokerStore.cashSession != nil,
          !isSettlingAbandonedCashSession else { return }
    isSettlingAbandonedCashSession = true
    defer { isSettlingAbandonedCashSession = false }
    do {
        let attempt = try abandonedSettlementAttempt()
        try await attempt.coordinator.leaveTable(
            settlementID: attempt.settlementID,
            cashOutID: attempt.cashOutID
        )
        abandonedCashSessionSettlementAttempt = nil
        abandonedCashSessionError = nil
    } catch {
        abandonedCashSessionError = "上次牌桌结算失败，请重试。"
    }
}
```

`joinCashTable` 在生成新会话编号前检查 `pokerStore.cashSession == nil`，否则抛出明确的 `AppSessionError.unsettledCashSession`。

- [ ] **步骤 4：在根视图接入启动任务和失败重试提示**

`AppRootView` 使用 `.task` 自动调用结算。失败时显示阻塞式恢复卡片，包含错误文字和“重试结算”按钮；结算期间显示进度并禁止新买入。

```swift
.task {
    await session.settleAbandonedCashSessionIfNeeded()
}
```

- [ ] **步骤 5：运行测试并确认通过**

运行步骤 2 的命令。预期：`CashTableEntryTests` 全部通过。

- [ ] **步骤 6：提交任务 1**

```bash
git add RiverClub/App/AppSession.swift RiverClub/App/AppRootView.swift RiverClubTests/CashTableEntryTests.swift
git commit -m "fix: 自动结算遗留牌桌并恢复买入"
```

### 任务 2：明确锦标赛报名按钮的高对比状态

**文件：**

- 修改：`RiverClub/Features/Tournaments/TournamentsView.swift`
- 创建：`RiverClubTests/TournamentPresentationTests.swift`

**接口：**

- 消费：`TournamentSummary.entryChips` 和 `isRegistered`。
- 产出：`TournamentRegistrationPresentation`，包含 `title`、`style` 和 `isEnabled`；其嵌套 `Style` 包含 `.available`、`.registered`。

- [ ] **步骤 1：编写按钮展示模型失败测试**

```swift
func testPaidTournamentButtonUsesAvailableHighContrastStyle() {
    let presentation = TournamentRegistrationPresentation(
        entryChips: 8_000,
        isRegistered: false
    )
    XCTAssertEqual(presentation.title, "报名 · 8,000 筹码")
    XCTAssertEqual(presentation.style, .available)
    XCTAssertTrue(presentation.isEnabled)
}

func testRegisteredTournamentButtonUsesDistinctDisabledStyle() {
    let presentation = TournamentRegistrationPresentation(
        entryChips: 0,
        isRegistered: true
    )
    XCTAssertEqual(presentation.title, "已报名")
    XCTAssertEqual(presentation.style, .registered)
    XCTAssertFalse(presentation.isEnabled)
}
```

- [ ] **步骤 2：运行测试并确认正确失败**

运行：

```bash
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:RiverClubTests/TournamentPresentationTests
```

预期：编译失败，提示展示模型尚未定义。

- [ ] **步骤 3：实现纯展示模型并应用明确配色**

可报名按钮使用 `.tint(RCTheme.gold)` 和 `.foregroundStyle(RCTheme.background)`；已报名按钮不依赖系统自动降低透明度，改用明确的 `RCTheme.surfaceRaised` 背景与 `RCTheme.secondaryText` 前景，并保持“已报名”文案和禁用语义。

```swift
struct TournamentRegistrationPresentation: Equatable {
    enum Style: Equatable { case available, registered }
    let title: String
    let style: Style
    let isEnabled: Bool
}
```

- [ ] **步骤 4：运行测试并确认通过**

运行步骤 2 的命令。预期：展示测试全部通过。

- [ ] **步骤 5：提交任务 2**

```bash
git add RiverClub/Features/Tournaments/TournamentsView.swift RiverClubTests/TournamentPresentationTests.swift
git commit -m "fix: 提高锦标赛报名按钮对比度"
```

### 任务 3：让存档列表严格适配横屏安全宽度

**文件：**

- 修改：`RiverClub/Features/History/HandHistoryView.swift`
- 修改：`RiverClubTests/HandHistoryLayoutTests.swift`

**接口：**

- 消费：`GeometryProxy.size.width`。
- 产出：`HandHistoryLayout.safeCanvas(width:height:)` 返回动态 `filterWidth` 和 `contentWidth`；`HandHistoryRowLayout` 增加 `potLineLimit` 与结果区完整宽度约束。

- [ ] **步骤 1：把截图对应宽度写成失败测试**

测试传入路由内容区实际宽度 726 点，验证页面分配总宽度不超过容器，列表宽度大于等于紧凑行最小宽度，并且结果区不少于完整显示 `-140,000` 和底池说明所需的 112 点。

```swift
func testCompactLandscapeHistoryKeepsRightResultInsideRoutedCanvas() {
    let canvas = HandHistoryLayout.safeCanvas(width: 726, height: 424)
    let row = HandHistoryLayout.rowMetrics(contentWidth: canvas.contentWidth)

    XCTAssertLessThanOrEqual(
        canvas.filterWidth + 16 + canvas.contentWidth + 40,
        726
    )
    XCTAssertLessThanOrEqual(row.minimumWidth, canvas.contentWidth)
    XCTAssertGreaterThanOrEqual(row.deltaWidth, 112)
}
```

- [ ] **步骤 2：运行测试并确认正确失败**

运行：

```bash
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:RiverClubTests/HandHistoryLayoutTests
```

预期：固定 220 点筛选栏导致列表可用宽度不足，断言失败。

- [ ] **步骤 3：实现顶层统一布局计算**

`HandHistoryView` 的列表状态使用 `GeometryReader`，将实际路由内容宽度传给 `safeCanvas`，并把动态筛选栏宽度和内容宽度应用到两个子视图。紧凑宽度下筛选栏缩为 184 点，行指标使用更紧凑但仍可读的牌面和间距。

```swift
GeometryReader { proxy in
    let layout = HandHistoryLayout.safeCanvas(
        width: proxy.size.width,
        height: proxy.size.height
    )
    HStack(spacing: 16) {
        HandHistoryFilterPanel(/* ... */)
            .frame(width: layout.filterWidth)
        HandHistoryContent(/* ... */)
            .frame(width: layout.contentWidth)
    }
    .padding(20)
}
```

存档行中的输赢金额使用 `.lineLimit(1)` 和 `.minimumScaleFactor(0.75)`，底池说明允许两行，并保持固定结果区宽度，确保右边界不超出列表。

- [ ] **步骤 4：运行测试并确认通过**

运行步骤 2 的命令。预期：`HandHistoryLayoutTests` 全部通过。

- [ ] **步骤 5：提交任务 3**

```bash
git add RiverClub/Features/History/HandHistoryView.swift RiverClubTests/HandHistoryLayoutTests.swift
git commit -m "fix: 防止横屏存档右侧信息被裁切"
```

### 任务 4：界面回归与完整验证

**文件：**

- 修改：`RiverClubUITests/LandscapeLayoutUITests.swift`

**接口：**

- 消费：现有界面辅助功能标识与前三个任务的实现。
- 产出：iPhone 横屏下按钮可读性和存档安全边界的自动回归保护。

- [ ] **步骤 1：编写界面失败断言**

在横屏测试中进入锦标赛，验证报名按钮存在且可读；进入“我的牌局”后读取 `history.list` 和所有 `history.row.*`，断言每一行的 `frame.maxX` 不超过窗口的 `frame.maxX`，且行的结果标签存在。

```swift
let windowFrame = app.windows.element(boundBy: 0).frame
let rows = app.buttons.matching(
    NSPredicate(format: "identifier BEGINSWITH 'history.row.'")
)
for index in 0..<rows.count {
    XCTAssertLessThanOrEqual(rows.element(boundBy: index).frame.maxX, windowFrame.maxX)
}
```

- [ ] **步骤 2：运行界面测试并确认修复后的断言通过**

运行：

```bash
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:RiverClubUITests/LandscapeLayoutUITests
```

预期：界面测试通过，窗口为横屏，按钮和存档行均在窗口范围内。

- [ ] **步骤 3：运行完整单元测试与界面测试**

运行：

```bash
swift test --package-path Packages/PokerCore
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:RiverClubTests
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:RiverClubUITests/CoreFlowUITests -only-testing:RiverClubUITests/LandscapeLayoutUITests -only-testing:RiverClubUITests/TableDepartureUITests
```

预期：所有测试通过，无失败用例。

- [ ] **步骤 4：构建通用 iOS 测试产物并检查工作区**

```bash
xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub -destination 'generic/platform=iOS'
git diff --check
git status --short
```

预期：构建成功，`git diff --check` 无输出，仅保留本任务预期修改。

- [ ] **步骤 5：提交回归测试与说明**

```bash
git add RiverClubUITests/LandscapeLayoutUITests.swift
git commit -m "test: 验证买入按钮与存档横屏修复"
```
