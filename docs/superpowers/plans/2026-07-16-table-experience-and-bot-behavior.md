# River Club 牌桌体验与机器人行为修复实施计划

> **供代理执行：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项执行。所有步骤使用复选框跟踪。

**目标：** 修复横屏大厅与牌桌布局、实时牌型、机器人集体全下、赢家动画、头像不一致和缺少离桌入口的问题。

**架构：** 保留现有 `PokerCore → PokerSession → PokerCoordinator → RiverClub` 边界。牌型与动画只使用安全牌桌投影；机器人在现有规则评估器中增加全下资格和底池比例下注；离桌通过专用核心动作、协调器加速结算和存储幂等退款完成。

**技术栈：** Swift 6、SwiftUI、Observation、Swift Testing、XCTest、XcodeGen、iOS 横屏。

## 全局约束

- 所有说明文档和 Git/GitHub 提交信息使用中文。
- iPhone 横屏侧栏固定为 `168pt`，水平内边距为 `10pt`。
- 公共牌不小于 `46×62pt`，本人手牌不小于 `42×57pt`，机器人手牌不小于 `34×46pt`。
- 牌型提示只能读取本人手牌和已公开公共牌。
- 机器人不能访问其他玩家底牌、牌堆、随机种子、恢复检查点或存档最终牌面。
- 玩家确认离桌后自动弃牌、合法结算、幂等退款，并返回进入牌桌前的页面。
- 所有产品代码必须遵循测试驱动：先看到目标测试失败，再编写最小实现。
- 直接在用户已授权的 `main` 当前工作目录开发，不创建工作树。

---

## 文件结构

新增：

- `RiverClub/Features/Table/CurrentHandPresentation.swift`：安全生成起手牌和正式中文牌型。
- `Packages/PokerCore/Sources/PokerBot/Strategy/BotBetSizing.swift`：底池比例下注和全下资格。
- `RiverClubTests/CurrentHandPresentationTests.swift`：实时牌型测试。
- `Packages/PokerCore/Tests/PokerBotTests/BotBetSizingTests.swift`：机器人下注和全下资格测试。
- `Packages/PokerCore/Tests/PokerCoordinatorTests/TableDepartureTests.swift`：进行中离桌与加速结算测试。
- `RiverClubUITests/TableDepartureUITests.swift`：离桌确认和返回来源页面 UI 测试。

修改：

- `RiverClub/DesignSystem/AppSidebar.swift`：侧栏宽度和间距。
- `RiverClub/Features/Table/PokerTableView.swift`：牌型、牌面、赢家筹码动画和离桌按钮。
- `RiverClub/Features/Table/PokerSeatView.swift`：统一圆形头像和座位尺寸。
- `RiverClub/Features/Table/TableCardView.swift`：支持不同展示尺寸下的清晰字号。
- `RiverClub/Features/Table/TableInteractionModels.swift`：奖励动画展示和离桌请求状态。
- `RiverClub/App/AppRootView.swift`：离桌确认全局模态和来源页面回跳。
- `RiverClub/App/AppSession.swift`：离桌业务标识、执行、重试和错误状态。
- `Packages/PokerCore/Sources/PokerCore/Game/HoldemGame.swift`：专用离桌弃牌入口。
- `Packages/PokerCore/Sources/PokerCore/Game/HoldemEngine.swift`：不伪造当前行动者的离桌弃牌转换。
- `Packages/PokerCore/Sources/PokerSession/Cash/CashGameSession.swift`：持久化离桌弃牌后的检查点。
- `Packages/PokerCore/Sources/PokerSession/Store/LocalPokerStore.swift`：协调器所需的安全离桌动作。
- `Packages/PokerCore/Sources/PokerBot/Decision/BotDecisionEngine.swift`：使用新候选资格和下注尺度。
- `Packages/PokerCore/Sources/PokerBot/Strategy/RuleBasedEvaluator.swift`：不再无条件加入全下候选。
- `Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableCoordinator.swift`：取消任务、离桌弃牌、加速完成与保存。
- `RiverClubTests/PokerTableLayoutTests.swift`、`PokerTableInteractionTests.swift`、`AppSessionTests.swift`：布局、动画和离桌状态。
- `Packages/PokerCore/Tests/PokerBotTests/BotDecisionEngineTests.swift`、`BotDecisionPropertyTests.swift`：决策分布回归。
- `RiverClubUITests/LandscapeLayoutUITests.swift`、`CoreFlowUITests.swift`：横屏布局和结算展示。

---

### 任务 1：缩窄侧栏并重排九人牌桌

**接口：**

- 产出 `AppSidebar.landscapePhoneWidth == 168`。
- 产出 `PokerTableLayout.communityCardSize`、`humanHoleCardSize`、`botHoleCardSize`。
- 后续任务使用这些令牌绘制牌型和奖励动画。

- [ ] **步骤 1：修改布局测试，先表达新规格**

在 `RiverClubTests/PokerTableLayoutTests.swift` 增加：

```swift
func testApprovedLandscapeCardAndSidebarMetrics() {
    XCTAssertEqual(AppSidebar.landscapePhoneWidth, 168)
    XCTAssertGreaterThanOrEqual(PokerTableLayout.communityCardSize.width, 46)
    XCTAssertGreaterThanOrEqual(PokerTableLayout.communityCardSize.height, 62)
    XCTAssertGreaterThanOrEqual(PokerTableLayout.humanHoleCardSize.width, 42)
    XCTAssertGreaterThanOrEqual(PokerTableLayout.humanHoleCardSize.height, 57)
    XCTAssertGreaterThanOrEqual(PokerTableLayout.botHoleCardSize.width, 34)
    XCTAssertGreaterThanOrEqual(PokerTableLayout.botHoleCardSize.height, 46)
}
```

把旧的 `testPlayableTableDoesNotExposeBackOrExitControl` 改为要求存在离桌接口：

```swift
func testPlayableTableExposesDepartureControl() throws {
    let source = try pokerTableViewSource()
    XCTAssertTrue(source.contains("table.leave"))
    XCTAssertTrue(source.contains("onRequestLeave"))
}
```

- [ ] **步骤 2：运行测试并确认失败**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
-destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
-only-testing:RiverClubTests/PokerTableLayoutTests CODE_SIGNING_ALLOWED=NO
```

预期：因新布局令牌和离桌接口尚不存在而失败。

- [ ] **步骤 3：实现布局令牌和圆形头像**

在 `AppSidebar` 增加：

```swift
static let landscapePhoneWidth: CGFloat = 168
static let horizontalPadding: CGFloat = 10
```

在 `PokerTableLayout` 增加：

```swift
static let communityCardSize = CGSize(width: 46, height: 62)
static let humanHoleCardSize = CGSize(width: 42, height: 57)
static let botHoleCardSize = CGSize(width: 34, height: 46)
```

调整 `seatSize`、`seatContentSize`、九座位坐标和中心区域，确保现有三个画布的座位矩形互不相交。

把 `PokerSeatView` 的头像抽成始终存在的圆形：

```swift
Text(initials)
    .frame(width: 30, height: 30)
    .background(avatarFill, in: Circle())
    .overlay { Circle().stroke(avatarStroke, lineWidth: 1) }
```

- [ ] **步骤 4：运行布局测试**

预期：`PokerTableLayoutTests` 全部通过。

- [ ] **步骤 5：提交**

```bash
git add RiverClub/DesignSystem/AppSidebar.swift \
RiverClub/Features/Table/PokerTableView.swift \
RiverClub/Features/Table/PokerSeatView.swift \
RiverClub/Features/Table/TableCardView.swift \
RiverClubTests/PokerTableLayoutTests.swift
git commit -m "fix: 优化横屏侧栏牌面与九人座位布局"
```

---

### 任务 2：实时展示本人起手牌和当前牌型

**接口：**

- 新增 `CurrentHandPresentation.text(holeCards:communityCards:) -> String?`。
- 输入只允许本人手牌和公共牌。
- `PokerTableView` 在公共牌下方调用该接口。

- [ ] **步骤 1：写失败测试**

创建 `RiverClubTests/CurrentHandPresentationTests.swift`：

```swift
func testPreflopDescribesPairSuitedAndOffsuit() throws {
    XCTAssertEqual(
        CurrentHandPresentation.text(
            holeCards: [try card(.ace, .spades), try card(.ace, .hearts)],
            communityCards: []
        ),
        "起手牌：AA 对子"
    )
}

func testBoardProducesBestFiveCardChineseRank() throws {
    XCTAssertEqual(
        CurrentHandPresentation.text(
            holeCards: [try card(.king, .diamonds), try card(.seven, .hearts)],
            communityCards: [
                try card(.king, .hearts), try card(.ten, .hearts),
                try card(.nine, .clubs), try card(.nine, .hearts),
                try card(.two, .hearts),
            ]
        ),
        "当前牌型：两对，K 和 9"
    )
}
```

- [ ] **步骤 2：运行测试并确认类型不存在**

运行 `RiverClubTests/CurrentHandPresentationTests`，预期编译失败。

- [ ] **步骤 3：实现展示模型**

创建 `CurrentHandPresentation.swift`：

```swift
enum CurrentHandPresentation {
    static func text(holeCards: [Card], communityCards: [Card]) -> String? {
        guard holeCards.count == 2 else { return nil }
        if communityCards.count < 3 {
            return "起手牌：\(startingHandText(holeCards))"
        }
        guard let rank = try? HandEvaluator.best(of: holeCards + communityCards) else {
            return nil
        }
        return "当前牌型：\(rankText(rank))"
    }
}
```

实现所有九类 `HandCategory` 的中文名称和点数文本。

- [ ] **步骤 4：接入牌桌**

从 `state.seats.first(where: \.isHuman)` 只提取 `faceUp` 手牌，与 `state.communityCards` 一起传入展示模型；文本放在公共牌下方、底池上方，增加 `table.currentHand` 标识。

- [ ] **步骤 5：运行测试并提交**

```bash
git add RiverClub/Features/Table/CurrentHandPresentation.swift \
RiverClub/Features/Table/PokerTableView.swift \
RiverClubTests/CurrentHandPresentationTests.swift
git commit -m "feat: 实时展示本人起手牌与当前牌型"
```

---

### 任务 3：修复机器人下注尺度和全下资格

**接口：**

- 新增 `BotBetSizing.target(...) -> Chips`。
- 新增 `BotAllInEligibility.isEligible(...) -> Bool`。
- `RuleBasedEvaluator.legalCandidates` 接收 `RuleEvaluation` 与 `BotSettings`，只有符合资格才加入 `.allIn`。

- [ ] **步骤 1：写下注与资格失败测试**

创建 `BotBetSizingTests.swift`，覆盖：

```swift
@Test func 默认下注尺度使用百分之六十六点五底池而不是半副筹码() throws {
    let target = try BotBetSizing.target(
        minimum: Chips(400), maximum: Chips(20_000),
        currentCommitment: Chips(0), pot: Chips(1_000), sizing: 50
    )
    #expect(target == Chips(665))
}

@Test func 深筹码中等牌力没有全下资格() {
    #expect(!BotAllInEligibility.isEligible(
        strength: 6_000, simulatedEquity: nil,
        effectiveStackBigBlinds: 100, potOddsBasisPoints: 2_500,
        model: .balanced, forcedShortCall: false
    ))
}

@Test func 十二个大盲和强牌保留合理全下() {
    #expect(BotAllInEligibility.isEligible(
        strength: 7_000, simulatedEquity: nil,
        effectiveStackBigBlinds: 12, potOddsBasisPoints: 3_000,
        model: .balanced, forcedShortCall: false
    ))
}
```

- [ ] **步骤 2：运行测试并确认失败**

运行：

```bash
cd Packages/PokerCore
swift test --filter PokerBotTests.BotBetSizing
```

预期：新类型不存在。

- [ ] **步骤 3：实现底池比例下注**

`BotBetSizing.target` 使用：

```swift
let basisPoints = 3_300 + sizing * 67
let potAmount = pot.rawValue * basisPoints / 10_000
let desired = currentCommitment.rawValue + max(minimumIncrement, potAmount)
return Chips(rawValue: min(maximum.rawValue, max(minimum.rawValue, desired)))!
```

所有加减乘使用溢出检查。

- [ ] **步骤 4：实现全下资格并改决策引擎**

资格规则严格对应规格中的 `12BB`、`8,500`、困难模式 `8,000` 和激进模型组合阈值。普通 `.bet`、`.raise` 调用 `BotBetSizing`，不再按最小值到最大筹码插值。

- [ ] **步骤 5：增加决策分布回归**

在 `BotDecisionPropertyTests.swift` 增加深筹码中等牌力的 `1_000` 个确定性种子统计，断言 `.allIn` 次数为 `0`；同时保留短筹码和强牌可产生 `.allIn` 的固定种子测试。

- [ ] **步骤 6：运行 PokerBot 全量测试并提交**

```bash
swift test --filter PokerBotTests
git add Packages/PokerCore/Sources/PokerBot \
Packages/PokerCore/Tests/PokerBotTests
git commit -m "fix: 纠正机器人下注尺度与全下决策"
```

---

### 任务 4：实现真实赢家筹码动画

**接口：**

- `TableAnimationPresentation.awardTargetSeat: SeatID?`
- `awardAmount: Chips?`
- `awardProgress: CGFloat`
- `PokerTableLayout.vectorFromPot(to:seat:canvas:) -> CGVector`

- [ ] **步骤 1：写失败测试**

在 `PokerTableInteractionTests.swift` 增加：

```swift
func testAwardPotMovesChipsTowardWinnerAndKeepsAmount() throws {
    let winner = try SeatID(3)
    let amount = try Chips(3_600)
    var presentation = TableAnimationPresentation()
    presentation.begin(.awardPot(seat: winner, amount: amount, potIndex: 0), token: 9)
    presentation.advance(token: 9)

    XCTAssertEqual(presentation.awardTargetSeat, winner)
    XCTAssertEqual(presentation.awardAmount, amount)
    XCTAssertEqual(presentation.awardProgress, 1)
}
```

- [ ] **步骤 2：运行并确认失败**

运行 `PokerTableInteractionTests`，预期新属性不存在。

- [ ] **步骤 3：实现展示状态和坐标转换**

`TableAnimationPresentation` 从 `.awardPot` 保留目标、金额和进度。`PokerTableView` 使用中央底池坐标与 `PokerTableLayout.positions` 中目标座位坐标计算位移，绘制独立筹码层：

```swift
awardChipStack
    .offset(x: vector.dx * progress, y: vector.dy * progress)
    .accessibilityLabel("\(winnerName)赢得\(amount.rawValue)")
```

多人奖励按协调器现有事件顺序逐个展示；减少动态效果时直接显示赢家文字与高亮。

- [ ] **步骤 4：运行动画和协调器测试并提交**

```bash
git add RiverClub/Features/Table/PokerTableView.swift \
RiverClub/Features/Table/TableInteractionModels.swift \
RiverClubTests/PokerTableInteractionTests.swift \
Packages/PokerCore/Tests/PokerCoordinatorTests/TableAnimationTests.swift
git commit -m "feat: 展示赢家与底池筹码奖励动画"
```

---

### 任务 5：实现进行中安全离桌核心流程

**接口：**

- `HoldemGame.foldForDeparture(_ seat: SeatID) throws -> GameTransition`
- `LocalPokerStore.foldHumanForDeparture() throws -> GameTransition`
- `CashTableCoordinator.leaveTable(...) async throws`

- [ ] **步骤 1：写核心失败测试**

在 `CashGameSessionTests.swift` 和新建的 `TableDepartureTests.swift` 覆盖：

```swift
@Test func 非当前行动真人离桌可被专用动作标记弃牌且不伪造普通动作() throws {
    let fixture = try activeNineSeatGameWhereBotActs()
    let transition = try fixture.game.foldForDeparture(fixture.human)
    #expect(fixture.game.spectatorObservation()
        .publicSeats.first(where: { $0.id == fixture.human })?.hasFolded == true)
    #expect(transition.events.contains(.actionApplied(
        seat: fixture.human, action: .fold
    )))
}
```

同时验证不能对不存在、已弃牌或已完成手牌重复调用。

- [ ] **步骤 2：运行并确认失败**

预期：`foldForDeparture` 不存在。

- [ ] **步骤 3：实现核心专用转换**

在 `HoldemEngine` 增加只用于离桌的转换：

```swift
static func foldingForDeparture(
    _ seat: SeatID,
    in state: HoldemState
) throws -> EngineResult
```

它只把指定仍在牌局中的座位标记为弃牌、重新计算合法 `currentActor`，并在只剩一名有效玩家时进入摊牌；不能修改该玩家已投入筹码、不能访问或公开底牌。

- [ ] **步骤 4：贯通 Session 与 Store**

`CashGameSession` 保存新检查点；`LocalPokerStore` 使用现有原子保存模式写入。失败时内存状态回滚到调用前快照。

- [ ] **步骤 5：实现协调器离桌**

`CashTableCoordinator.leaveTable`：

1. 取消倒计时、机器人决策和当前操作版本。
2. 调用专用离桌弃牌。
3. 使用机器人服务或合法回退动作加速完成剩余牌局。
4. 提交待结算记录。
5. 调用既有幂等 `store.leave(businessID:)` 退款。

所有业务 ID 从 `AppSession` 注入，重试复用同一组 ID。

- [ ] **步骤 6：运行 PokerCore 全量测试并提交**

```bash
cd Packages/PokerCore
swift test
git add Sources/PokerCore Sources/PokerSession Sources/PokerCoordinator \
Tests/PokerCoreTests Tests/PokerSessionTests Tests/PokerCoordinatorTests
git commit -m "feat: 实现进行中自动弃牌与安全离桌结算"
```

---

### 任务 6：接入离桌确认、错误重试和来源页面返回

**接口：**

- `PokerTableView.onRequestLeave: () -> Void`
- `AppSession.requestTableDeparture()`、`cancelTableDeparture()`、`confirmTableDeparture() async`
- `TableDeparturePresentation` 驱动根视图模态。

- [ ] **步骤 1：写 AppSession 失败测试**

在 `AppSessionTests.swift` 增加：

```swift
@MainActor
func testDepartureConfirmationReturnsToEntryRouteAndDoesNotDoubleRefund() async throws {
    let fixture = try AppSessionFixture()
    let session = fixture.session
    session.open(.tableBrowser)
    try session.joinCashTable(fixture.table, buyIn: 16_000, autoTopUp: false)
    session.requestTableDeparture()
    await session.confirmTableDeparture()

    XCTAssertEqual(session.route, .tableBrowser)
    XCTAssertNil(session.selectedTable)
    XCTAssertNil(session.tableDepartureError)
}
```

增加取消确认、失败保留牌桌、重试复用业务标识测试。

- [ ] **步骤 2：运行并确认失败**

运行 `AppSessionTests`，预期离桌展示状态和方法不存在。

- [ ] **步骤 3：实现根级确认模态**

`AppRootView` 把原本未使用的 `tableReturnRoute` 接入离桌流程。确认层覆盖完整牌桌并使用：

```swift
.allowsHitTesting(false)
.accessibilityHidden(true)
```

隐藏背景；按钮标识：

- `table.leave`
- `table.leave.cancel`
- `table.leave.confirm`
- `table.leave.retry`

- [ ] **步骤 4：实现错误与重试**

确认后显示“正在结算并离桌”；失败时保持牌桌、显示中文错误并允许重试。成功后才清理 `tableCoordinator`、`selectedTable` 和离桌状态。

- [ ] **步骤 5：运行 RiverClubTests 并提交**

```bash
git add RiverClub/App/AppRootView.swift RiverClub/App/AppSession.swift \
RiverClub/Features/Table/PokerTableView.swift \
RiverClub/Features/Table/TableInteractionModels.swift \
RiverClubTests/AppSessionTests.swift RiverClubTests/PokerTableInteractionTests.swift
git commit -m "feat: 接入牌桌离桌确认与失败重试"
```

---

### 任务 7：UI 回归、中文说明和最终验证

**接口：**

- 不新增产品接口。
- 验证任务 1–6 在真实应用流程中协同工作。

- [ ] **步骤 1：增加横屏 UI 断言**

在 `LandscapeLayoutUITests.swift` 验证：

- 侧栏主内容宽度增加。
- `table.currentHand` 存在。
- 公共牌和本人手牌元素可见且不被座位遮挡。
- 九个 `table.seat.*` 均存在。
- `table.leave` 可点击。

- [ ] **步骤 2：增加离桌 UI 流程**

创建 `TableDepartureUITests.swift`：

```text
游客登录
→ 从全部牌桌进入并买入
→ 点击离桌
→ 取消并确认仍在牌桌
→ 再次点击离桌并确认
→ 等待后台结算
→ 返回全部牌桌
→ 验证余额只退还一次
```

- [ ] **步骤 3：增加赢家展示 UI 断言**

在测试模式使用确定性牌局种子，等待 `table.winnerAnnouncement`，验证包含赢家名称和奖励金额，并确认下一手按钮出现。

- [ ] **步骤 4：更新中文说明**

更新 `README.md` 的已实现功能和测试命令，说明机器人全下资格、牌型提示、赢家动画和离桌语义。

- [ ] **步骤 5：运行全量验证**

```bash
cd Packages/PokerCore
swift test
```

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
-destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
-only-testing:RiverClubTests CODE_SIGNING_ALLOWED=NO
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
-destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
-only-testing:RiverClubUITests/CoreFlowUITests \
-only-testing:RiverClubUITests/LandscapeLayoutUITests \
-only-testing:RiverClubUITests/TableDepartureUITests \
CODE_SIGNING_ALLOWED=NO
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub \
-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git diff --check
git status --short
```

预期：所有测试通过、通用 iOS 构建成功、无格式错误。

- [ ] **步骤 6：最终提交**

```bash
git add README.md RiverClubUITests
git commit -m "test: 验证牌桌体验机器人行为与安全离桌"
```

- [ ] **步骤 7：独立代码审查**

审查范围从本计划起始提交到最终提交，要求：

- Critical：0
- Important：0
- 机器人隐藏信息边界无回归。
- 资金守恒与离桌幂等无回归。
- iPhone Pro Max 横屏无新增遮挡。

