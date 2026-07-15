# River Club 普通桌 SwiftUI 可玩闭环实施计划

> **供代理执行者：** 必须逐任务使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 执行；所有步骤使用复选框跟踪。

**目标：** 把现有静态九人桌接入真实普通桌会话和公平机器人，使玩家能从买入开始完成一手、保存结果并进入下一手。

**架构：** 在现有 Swift Package 中新增不依赖 SwiftUI 的 `PokerCoordinator` 产品，位于 `PokerCore`、`PokerSession`、`PokerBot` 与 RiverClub 之间。协调器通过 package 安全接口读取机器人自己的观察，只向应用公开真人底牌和公开牌桌状态；`AppSession` 持有唯一 `LocalPokerStore`，买入、动作检查点和最终记录共享同一真值来源。

**技术栈：** Swift 6、SwiftUI、Observation、Swift Concurrency、Swift Testing、XCTest、XcodeGen；最低 iOS 18、macOS 14。

## 全局约束

- 所有说明文档、计划、交付说明和 Git/GitHub 提交信息使用中文。
- 目标设备为 iPhone 16 Pro Max，全程横屏，仅支持 iPhone。
- 普通桌固定九人：一个真人、八个本地机器人。
- 真人买入范围严格为 40–100 个大盲。
- SwiftUI 不判断扑克规则，不取得机器人底牌、牌堆、种子或恢复检查点。
- 所有动作必须再次通过 `PokerCore` 验证，机器人失败时能过牌则过牌，否则弃牌。
- 本手冻结机器人设置；设置修改从下一手生效。
- 正常牌桌不显示弃牌玩家底牌；所有最终底牌只在完成后的存档中保留。
- 每个生产改动先写失败测试，再写最小实现；每个任务完成后独立中文提交。

---

## 文件结构

新增 Swift Package 产品：

- `Packages/PokerCore/Sources/PokerCoordinator/Domain/TableViewState.swift`：公开安全牌桌状态。
- `Packages/PokerCore/Sources/PokerCoordinator/Domain/TableIntent.swift`：真人操作意图和动态控件模型。
- `Packages/PokerCore/Sources/PokerCoordinator/Animation/TableAnimationEvent.swift`：安全动画事件与节奏。
- `Packages/PokerCore/Sources/PokerCoordinator/Runtime/TableRuntimeDependencies.swift`：时钟、标识和种子依赖。
- `Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableCoordinator.swift`：主状态机。
- `Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableProjection.swift`：会话观察到 UI 状态的纯映射。
- `Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableActionPipeline.swift`：真人动作、机器人动作和轮次推进。
- `Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableAnimationMapper.swift`：规则事件到动画事件的纯映射。
- `Packages/PokerCore/Tests/PokerCoordinatorTests/`：协调器单元、属性、边界和性能测试。
- `Packages/PokerCore/Tests/PokerCoordinatorTests/Support/CoordinatorTestSupport.swift`：临时存储、可控时钟、确定性机器人和场景构造器。
- `Packages/PokerCore/Tests/PokerCoordinatorPublicAPITests/`：普通导入隐藏信息负向探针。

修改会话安全边界：

- `Packages/PokerCore/Sources/PokerSession/Cash/CashShowdownObservation.swift`：仅 package 可见的安全摊牌数据。
- `Packages/PokerCore/Sources/PokerSession/Store/LocalPokerStore.swift`：机器人补充与安全摊牌接口。

修改 RiverClub：

- `RiverClub/App/AppSession.swift`：唯一 `LocalPokerStore`、真实余额和协调器生命周期。
- `RiverClub/App/AppRootView.swift`：买入事务和协调器注入。
- `RiverClub/Features/Lobby/BuyInSheet.swift`：40–100BB 买入范围。
- `RiverClub/Features/Table/PokerTableView.swift`：真实状态、动画和错误面板。
- `RiverClub/Features/Table/BetControlBar.swift`：动态合法按钮和下注范围。
- `RiverClub/Features/Table/PokerSeatView.swift`：真实公开座位状态。
- `project.yml`：加入 `PokerCoordinator` 产品依赖。

---

### 任务 1：建立 PokerCoordinator 产品和可信会话接口

**文件：**
- 修改：`Packages/PokerCore/Package.swift`
- 新建：`Packages/PokerCore/Sources/PokerSession/Cash/CashShowdownObservation.swift`
- 修改：`Packages/PokerCore/Sources/PokerSession/Store/LocalPokerStore.swift`
- 新建：`Packages/PokerCore/Sources/PokerCoordinator/PokerCoordinator.swift`
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorTests/PokerCoordinatorBoundaryTests.swift`
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorTests/Support/CoordinatorTestSupport.swift`

**接口：**
- 消费：`LocalPokerStore`、`PendingCashHand`、`CompletedHandRecord`。
- 产出：`PokerCoordinator` 产品；package `refillBotSeat(_:to:)`、`pendingShowdownObservation`、`activeCashConfig`、`playerObservation(for:)`。

- [ ] **步骤 1：写失败测试，锁定机器人补充和安全摊牌边界**

```swift
import PokerCore
import PokerSession
import Testing
@testable import PokerCoordinator

@Test func 归零机器人补至目标筹码且真人余额不变() throws {
    let fixture = try CoordinatorStoreFixture.finishedHandWithBustedBot()
    let balance = fixture.store.accountBalance
    try fixture.store.refillBotSeat(fixture.bustedBot, to: try Chips(10_000))
    #expect(fixture.store.cashSession?.seats.first { $0.id == fixture.bustedBot }?.stack == try Chips(10_000))
    #expect(fixture.store.accountBalance == balance)
}

@Test func 安全摊牌观察排除已弃牌底牌() throws {
    let fixture = try CoordinatorStoreFixture.pendingShowdown()
    let showdown = try #require(fixture.store.pendingShowdownObservation)
    #expect(showdown.cardsBySeat[fixture.showdownSeat]?.count == 2)
    #expect(showdown.cardsBySeat[fixture.foldedSeat] == nil)
}
```

- [ ] **步骤 2：运行测试并确认因接口不存在而失败**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter PokerCoordinatorBoundaryTests
```

预期：编译失败，提示找不到 `PokerCoordinator`、`refillBotSeat` 或 `pendingShowdownObservation`。

- [ ] **步骤 3：增加产品、target 和测试 target**

在 `Package.swift` 中增加：

```swift
.library(name: "PokerCoordinator", targets: ["PokerCoordinator"])
```

以及：

```swift
.target(
    name: "PokerCoordinator",
    dependencies: ["PokerCore", "PokerSession", "PokerBot"]
),
.testTarget(
    name: "PokerCoordinatorTests",
    dependencies: ["PokerCoordinator", "PokerCore", "PokerSession", "PokerBot"]
),
.testTarget(
    name: "PokerCoordinatorPublicAPITests",
    dependencies: ["PokerCoordinator", "PokerCore"]
)
```

- [ ] **步骤 4：实现安全摊牌观察和机器人补充事务**

`CashShowdownObservation.swift`：

```swift
import PokerCore

package struct CashShowdownObservation: Equatable, Sendable {
    package let cardsBySeat: [SeatID: [Card]]

    package init(record: CompletedHandRecord) {
        cardsBySeat = record.holeCardsBySeat.filter {
            record.handRanksBySeat[$0.key] != nil
        }
    }
}
```

在 `LocalPokerStore` 中增加事务接口；只允许非真人座位，并要求当前为 `.readyForHand`：

```swift
package func refillBotSeat(_ seat: SeatID, to target: Chips) throws {
    try transact { state in
        guard var session = state.activeCashSession,
              seat != session.humanSeat,
              let current = session.stacks[seat],
              current.rawValue == 0,
              target.rawValue > 0 else {
            throw PokerSessionError.invalidTable
        }
        try session.addChips(
            try Chips(target.rawValue - current.rawValue),
            to: seat
        )
        state.activeCashSession = session
    }
}

package var pendingShowdownObservation: CashShowdownObservation? {
    committed.activeCashSession?.pendingHand.map {
        CashShowdownObservation(record: $0.record)
    }
}

package var activeCashConfig: HandConfig? {
    committed.activeCashSession?.config
}
```

`PokerCoordinator.swift` 只导入三个依赖模块，不公开内部恢复类型。

同一步建立 `CoordinatorTestSupport.swift`。它统一提供 `CoordinatorStoreFixture`、`CoordinatorScenario`、`ManualTableClock`、`RecordingBotDecisionService`、`SuspendedBotDecisionService`、`FailOnceSessionRepository`、`decodeLegalActions(_:)`、`decodeCards(_:)` 和 `makeSafeTableViewState()`。场景构造器至少实现本计划中实际调用的 `finishedHandWithBustedBot`、`pendingShowdown`、`readyWithBustedBot`、`humanFacingRaise`、`humanCanRaiseToAllIn`、`humanCanCheck`、`botOpeningAction`、`pendingSettlement`、`botThinking` 九个入口。所有夹具使用临时目录、`FixedSessionClock`、固定 `HandID`/`BusinessID`/种子，并在 `deinit` 删除自己的临时目录；后续测试不再重复搭建九人桌。

- [ ] **步骤 5：运行目标测试和 PokerSession 回归测试**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter PokerCoordinatorBoundaryTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter PokerSessionTests
```

预期：新增测试通过，现有会话事务测试全部通过。

- [ ] **步骤 6：中文提交**

```bash
git add Packages/PokerCore/Package.swift Packages/PokerCore/Sources/PokerSession Packages/PokerCore/Sources/PokerCoordinator Packages/PokerCore/Tests/PokerCoordinatorTests
git commit -m "feat: 建立普通桌协调器安全边界"
```

---

### 任务 2：定义公开安全牌桌状态和动态操作模型

**文件：**
- 新建：`Packages/PokerCore/Sources/PokerCoordinator/Domain/TableViewState.swift`
- 新建：`Packages/PokerCore/Sources/PokerCoordinator/Domain/TableIntent.swift`
- 新建：`Packages/PokerCore/Sources/PokerCoordinator/Animation/TableAnimationEvent.swift`
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorTests/TableViewStateTests.swift`

**接口：**
- 消费：`Card`、`Chips`、`SeatID`、`PlayerAction`。
- 产出：`TableViewState`、`TableFlowPhase`、`TableSeatProfile`、`TableSeatState`、`TableActionControls`、`TableIntent`、`TableAnimationEvent`。

- [ ] **步骤 1：写失败测试，验证控件映射和状态无隐藏字段**

```swift
@Test func 面对下注时显示弃牌跟注和合法加注范围() throws {
    let legal = try decodeLegalActions(
        #"{"canFold":true,"canCheck":false,"callAmount":200,"minimumBet":null,"minimumRaiseTo":600,"maximumRaiseTo":2000,"canAllIn":true}"#
    )
    let controls = try TableActionControls(legalActions: legal)
    #expect(controls.canFold)
    #expect(controls.middle == .call(try Chips(200)))
    #expect(controls.aggressive == .raise(minimum: try Chips(600), maximum: try Chips(2_000), canAllIn: true))
}

@Test func 安全状态编码只包含真人明牌和公开数据() throws {
    let data = try JSONEncoder().encode(makeSafeTableViewState())
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(!text.contains("deck"))
    #expect(!text.contains("seed"))
    #expect(!text.contains("checkpoint"))
    #expect(!text.contains("opponentHoleCards"))
}
```

- [ ] **步骤 2：运行测试并确认类型不存在**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter TableViewStateTests
```

预期：编译失败，提示找不到 `TableActionControls` 和 `TableViewState`。

- [ ] **步骤 3：实现领域类型**

核心签名固定为：

```swift
public enum TableFlowPhase: String, Codable, Equatable, Sendable {
    case preparingHand, dealing, waitingForHuman, botThinking
    case animatingAction, revealingBoard, settling, savingResult
    case awaitingNextHand, saveFailed, suspended
}

public enum TableCardState: Codable, Equatable, Sendable {
    case faceDown
    case faceUp(Card)
}

public struct TableSeatProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: SeatID
    public let displayName: String

    public init(id: SeatID, displayName: String) throws {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PokerCoordinatorError.missingObservation }
        self.id = id
        self.displayName = name
    }
}

public struct TableSeatState: Codable, Equatable, Identifiable, Sendable {
    public let id: SeatID
    public let displayName: String
    public let stack: Chips
    public let committedThisStreet: Chips
    public let hasFolded: Bool
    public let isAllIn: Bool
    public let isDealer: Bool
    public let isCurrentActor: Bool
    public let cards: [TableCardState]
}

public enum TableMiddleAction: Codable, Equatable, Sendable {
    case check
    case call(Chips)
}

public enum TableAggressiveAction: Codable, Equatable, Sendable {
    case bet(minimum: Chips, maximum: Chips, canAllIn: Bool)
    case raise(minimum: Chips, maximum: Chips, canAllIn: Bool)
}

public struct TableActionControls: Codable, Equatable, Sendable {
    public let canFold: Bool
    public let middle: TableMiddleAction?
    public let aggressive: TableAggressiveAction?

    package init(legalActions: LegalActionSet) throws {
        canFold = legalActions.canFold
        middle = legalActions.canCheck
            ? .check
            : legalActions.callAmount.map(TableMiddleAction.call)

        if let minimum = legalActions.minimumBet,
           let maximum = legalActions.maximumRaiseTo,
           minimum <= maximum {
            aggressive = .bet(
                minimum: minimum,
                maximum: maximum,
                canAllIn: legalActions.canAllIn
            )
        } else if let minimum = legalActions.minimumRaiseTo,
                  let maximum = legalActions.maximumRaiseTo,
                  minimum <= maximum {
            aggressive = .raise(
                minimum: minimum,
                maximum: maximum,
                canAllIn: legalActions.canAllIn
            )
        } else {
            aggressive = nil
        }
    }
}

public enum TableIntent: Equatable, Sendable {
    case fold
    case middle
    case aggressive(amount: Chips)
    case nextHand
    case retrySave
}

public struct TableViewState: Codable, Equatable, Sendable {
    public let handID: String?
    public let stateVersion: Int
    public let phase: TableFlowPhase
    public let seats: [TableSeatState]
    public let communityCards: [Card]
    public let pot: Chips
    public let controls: TableActionControls?
    public let secondsRemaining: Int?
    public let winners: Set<SeatID>
    public let errorMessage: String?
    public let animation: TableAnimationEvent?
}

public enum TableAnimationKind: String, Codable, Equatable, Sendable {
    case dealHoleCard
    case postBlind
    case showAction
    case moveCommitmentToPot
    case streetChanged
    case revealCommunityCard
    case returnUncalledBet
    case awardPot
    case highlightWinner
}

public enum TableAnimationEvent: Codable, Equatable, Sendable {
    case dealHoleCard(seat: SeatID, card: TableCardState)
    case postBlind(seat: SeatID, amount: Chips)
    case showAction(seat: SeatID, action: PlayerAction)
    case moveCommitmentToPot(seat: SeatID, amount: Chips)
    case streetChanged(Street)
    case revealCommunityCard(card: Card, index: Int)
    case returnUncalledBet(seat: SeatID, amount: Chips)
    case awardPot(seat: SeatID, amount: Chips, potIndex: Int)
    case highlightWinner(SeatID)

    public var kind: TableAnimationKind {
        switch self {
        case .dealHoleCard: .dealHoleCard
        case .postBlind: .postBlind
        case .showAction: .showAction
        case .moveCommitmentToPot: .moveCommitmentToPot
        case .streetChanged: .streetChanged
        case .revealCommunityCard: .revealCommunityCard
        case .returnUncalledBet: .returnUncalledBet
        case .awardPot: .awardPot
        case .highlightWinner: .highlightWinner
        }
    }
}

public enum PokerCoordinatorError: Error, Equatable, Sendable {
    case invalidPhase
    case illegalIntent
    case missingObservation
    case chipArithmeticOverflow
    case saveFailed
    case suspended
}
```

`TableAnimationEvent` 只使用 `SeatID`、公开 `Card`、公开动作和金额；底牌事件使用 `TableCardState.faceDown` 或只对真人使用 `.faceUp`。同时定义 `TableAnimationKind` 以及 `TableAnimationEvent.kind` 计算属性，供动画顺序测试比较。

- [ ] **步骤 4：运行目标测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter TableViewStateTests
```

预期：控件映射和编码边界测试全部通过。

- [ ] **步骤 5：中文提交**

```bash
git add Packages/PokerCore/Sources/PokerCoordinator/Domain Packages/PokerCore/Sources/PokerCoordinator/Animation Packages/PokerCore/Tests/PokerCoordinatorTests/TableViewStateTests.swift
git commit -m "feat: 定义安全牌桌状态与操作意图"
```

---

### 任务 3：实现手牌启动、状态投影和机器人自动补充

**文件：**
- 新建：`Packages/PokerCore/Sources/PokerCoordinator/Runtime/TableRuntimeDependencies.swift`
- 新建：`Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableProjection.swift`
- 新建：`Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableCoordinator.swift`
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorTests/CashTableCoordinatorStartTests.swift`

**接口：**
- 消费：已入座的 `LocalPokerStore`、冻结 `BotSettings`。
- 产出：`CashTableCoordinator.init(store:humanSeat:seatProfiles:dependencies:)`、`startHand(settings:)`、安全 `state`。

- [ ] **步骤 1：写失败测试，覆盖自动发牌、设置冻结和归零机器人**

```swift
@Test @MainActor func 开始手牌自动补充机器人并发布安全发牌状态() async throws {
    let fixture = try CoordinatorStoreFixture.readyWithBustedBot()
    let coordinator = CashTableCoordinator(
        store: fixture.store,
        humanSeat: fixture.humanSeat,
        seatProfiles: fixture.seatProfiles,
        dependencies: .immediate(seed: 7)
    )
    try await coordinator.startHand(settings: .recommended)
    #expect(coordinator.state.handID == "hand-1")
    #expect(coordinator.state.seats.count == 9)
    #expect(coordinator.state.seats.first { $0.id == fixture.humanSeat }?.cards.count == 2)
    #expect(coordinator.state.seats.filter { $0.id != fixture.humanSeat }.allSatisfy {
        $0.cards == [.faceDown, .faceDown]
    })
    #expect(coordinator.frozenSettings == .recommended)
}
```

- [ ] **步骤 2：运行测试确认失败**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter CashTableCoordinatorStartTests
```

预期：编译失败，提示 `CashTableCoordinator` 不存在。

- [ ] **步骤 3：实现可注入运行依赖和纯投影**

```swift
public struct TableRuntimeDependencies: Sendable {
    public let nextHandID: @Sendable () throws -> HandID
    public let nextBusinessID: @Sendable (_ purpose: String) throws -> BusinessID
    public let nextSeed: @Sendable () -> UInt64
    public let sleep: @Sendable (_ duration: Duration) async throws -> Void
}
```

`CashTableProjection.make` 同时读取 `spectatorObservation`、`humanObservation()` 和协调器初始化时验证过的九个唯一 `TableSeatProfile`；对真人放入两张 `.faceUp`，其他已发牌座位只放两张 `.faceDown`。底池使用所有 `committedThisHand` 的受检和，当前真人行动时才构造 `TableActionControls`。资料缺座、重复或与会话座位集合不一致时，初始化直接抛出 `missingObservation`。

- [ ] **步骤 4：实现协调器开始手牌**

```swift
@MainActor @Observable
public final class CashTableCoordinator {
    public private(set) var state: TableViewState
    package private(set) var frozenSettings: BotSettings?

    public func startHand(settings: BotSettings) async throws {
        guard store.cashSession?.phase == .readyForHand else {
            throw PokerCoordinatorError.invalidPhase
        }
        frozenSettings = settings
        try refillBustedBotsToOneHundredBigBlinds()
        let transition = try store.startHand(
            id: dependencies.nextHandID(),
            seed: dependencies.nextSeed()
        )
        incrementStateVersion()
        try await present(transition)
        try refreshProjection()
        await scheduleCurrentActorIfReady()
    }
}
```

机器人目标筹码严格使用 `store.activeCashConfig.bigBlind * 100` 计算；配置缺失、乘法溢出或不能构造 `Chips` 时抛出 `PokerCoordinatorError.chipArithmeticOverflow`，禁止在协调器中猜测盲注，也不修改 `CashSessionView` 的持久化格式。

- [ ] **步骤 5：运行目标测试和全量 Package 测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter CashTableCoordinatorStartTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore
```

预期：目标测试通过，现有全部 Package 测试通过。

- [ ] **步骤 6：中文提交**

```bash
git add Packages/PokerCore/Sources/PokerCoordinator Packages/PokerCore/Sources/PokerSession Packages/PokerCore/Tests/PokerCoordinatorTests
git commit -m "feat: 实现普通桌手牌启动与安全投影"
```

---

### 任务 4：实现真人动态操作和 30 秒倒计时

**文件：**
- 新建：`Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableActionPipeline.swift`
- 修改：`Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableCoordinator.swift`
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorTests/HumanActionPipelineTests.swift`
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorTests/HumanTimeoutTests.swift`

**接口：**
- 消费：`TableIntent`、最新 `PlayerObservation.legalActions`。
- 产出：`send(_ intent:)`、单实例倒计时、自动轮次推进。

- [ ] **步骤 1：写失败测试，覆盖六类动作和过期金额**

```swift
@Test @MainActor func 真人意图只映射到最新合法动作() async throws {
    let scenario = try await CoordinatorScenario.humanFacingRaise()
    let coordinator = scenario.coordinator
    await #expect(throws: PokerCoordinatorError.illegalIntent) {
        try await coordinator.send(.aggressive(amount: try Chips(399)))
    }
    let version = coordinator.state.stateVersion
    try await coordinator.send(.aggressive(amount: try Chips(600)))
    #expect(coordinator.state.stateVersion > version)
}

@Test @MainActor func 最大下注映射为全下而不是越界加注() async throws {
    let scenario = try await CoordinatorScenario.humanCanRaiseToAllIn()
    let coordinator = scenario.coordinator
    try await coordinator.send(.aggressive(amount: try Chips(1_000)))
    let observation = try #require(scenario.store.humanObservation())
    #expect(observation.actions.last?.action == .allIn)
}
```

- [ ] **步骤 2：写失败测试，覆盖超时过牌、弃牌和单次触发**

```swift
@Test @MainActor func 三十秒超时优先过牌且只执行一次() async throws {
    let clock = ManualTableClock()
    let scenario = try await CoordinatorScenario.humanCanCheck(clock: clock)
    let coordinator = scenario.coordinator
    await clock.advance(by: .seconds(30))
    let first = try #require(scenario.store.humanObservation())
    #expect(first.actions.last?.action == .check)
    let actionCount = first.actions.count
    await clock.advance(by: .seconds(30))
    let second = try #require(scenario.store.humanObservation())
    #expect(second.actions.count == actionCount)
}
```

- [ ] **步骤 3：运行测试确认失败**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter HumanActionPipelineTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter HumanTimeoutTests
```

预期：失败，提示 `send`、倒计时或测试时钟尚未实现。

- [ ] **步骤 4：实现最新状态合法映射**

动作映射固定为：

```swift
switch intent {
case .fold where legal.canFold:
    return .fold
case .middle where legal.canCheck:
    return .check
case .middle where legal.callAmount != nil:
    return .call
case let .aggressive(amount) where amount == legal.maximumRaiseTo && legal.canAllIn:
    return .allIn
case let .aggressive(amount) where legal.minimumBet.map({ amount >= $0 }) == true:
    return .bet(amount)
case let .aggressive(amount) where legal.minimumRaiseTo.map({ amount >= $0 }) == true:
    return .raiseTo(amount)
default:
    throw PokerCoordinatorError.illegalIntent
}
```

每个 bet/raise 分支还必须验证 `amount <= maximumRaiseTo`。执行后取消倒计时、调用 `store.apply`、递增版本、播放动作事件并调用 `advanceIfRoundComplete`，直到产生下一行动者或进入结算。

- [ ] **步骤 5：实现 30 秒倒计时**

倒计时任务携带启动时的 `handID` 和 `stateVersion`。每秒更新 `secondsRemaining`；归零前重新读取真人最新合法集合并只提交一次 `.check` 或 `.fold`。任何成功动作、阶段变化、后台暂停或协调器释放都取消任务。

- [ ] **步骤 6：运行目标测试和属性测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter Human
```

预期：动作边界、最大值全下和倒计时测试全部通过。

- [ ] **步骤 7：中文提交**

```bash
git add Packages/PokerCore/Sources/PokerCoordinator/Cash Packages/PokerCore/Tests/PokerCoordinatorTests/HumanActionPipelineTests.swift Packages/PokerCore/Tests/PokerCoordinatorTests/HumanTimeoutTests.swift
git commit -m "feat: 实现真人操作与行动倒计时"
```

---

### 任务 5：接入八个公平机器人并串行完成一手

**文件：**
- 修改：`Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableCoordinator.swift`
- 修改：`Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableActionPipeline.swift`
- 新建：`Packages/PokerCore/Sources/PokerCoordinator/Runtime/BotDecisionServing.swift`
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorTests/BotTurnSchedulerTests.swift`
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorTests/CoordinatorHandPropertyTests.swift`

**接口：**
- 消费：package `playerObservation(for:)`、`BotDecisionRequest`、冻结 `BotSettings`。
- 产出：单机器人任务调度、状态版本拦截、完整一手自动推进。

- [ ] **步骤 1：写失败测试，验证串行顺序和安全观察**

```swift
@Test @MainActor func 八个机器人按当前行动者串行执行() async throws {
    let botService = RecordingBotDecisionService(action: .call)
    let scenario = try await CoordinatorScenario.botOpeningAction(
        botService: botService
    )
    let coordinator = scenario.coordinator
    try await coordinator.runUntilHumanOrSettlement()
    let calls = await botService.requests()
    #expect(calls.count > 0)
    #expect(calls.allSatisfy { $0.observation.viewer == $0.observation.currentActor })
    #expect(await botService.maximumConcurrentCalls() == 1)
}

@Test @MainActor func 旧版本机器人结果不会提交() async throws {
    let botService = SuspendedBotDecisionService()
    let scenario = try await CoordinatorScenario.botOpeningAction(botService: botService)
    let coordinator = scenario.coordinator
    let actionCount = try scenario.actionCount()
    let oldVersion = coordinator.state.stateVersion
    await coordinator.suspend()
    await botService.resume(with: .fold, stateVersion: oldVersion)
    #expect(coordinator.state.stateVersion > oldVersion)
    #expect(try scenario.actionCount() == actionCount)
}
```

- [ ] **步骤 2：运行测试确认失败**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter BotTurnSchedulerTests
```

- [ ] **步骤 3：实现可注入机器人服务和调度**

```swift
package protocol BotDecisionServing: Sendable {
    func decide(_ request: BotDecisionRequest) async -> BotDecision?
    func cancel(handID: String) async
}

extension BotDecisionService: BotDecisionServing {}
```

调度器只在 `cashSession.currentActor != humanSeat` 时创建任务：

```swift
guard let player = try store.playerObservation(for: actor) else {
    throw PokerCoordinatorError.missingObservation
}
let observation = try BotObservation(
    handID: handID.rawValue,
    stateVersion: stateVersion,
    config: handConfig,
    observation: player
)
let request = BotDecisionRequest(
    observation: observation,
    settings: frozenSettings,
    stableIdentity: "cash:\(sessionID.rawValue):seat:\(actor.rawValue)",
    seed: dependencies.nextSeed(),
    history: nil
)
```

结果提交前同时比较 handID、stateVersion 和 currentActor。成功后仍调用 `store.apply`；取消、旧版本或行动者不匹配的结果不提交。若服务在当前有效版本返回 nil，协调器重新读取该机器人的最新合法集合，能过牌则提交 `.check`，否则提交 `.fold`；若两者都不合法才进入牌桌错误面板，绝不重试模型或无限循环。

- [ ] **步骤 4：写并运行 200 手确定性属性测试**

`CoordinatorHandPropertyTests` 使用测试支持文件中的确定性合法动作机器人和零延迟时钟循环 200 手，不调用蒙特卡洛模型；断言每个动作均来自当时合法集合、同一时刻只有一个机器人任务、最终筹码守恒且每手进入 `.awaitingNextHand` 或明确 `.saveFailed`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter CoordinatorHandPropertyTests
```

预期：200 手全部完成且确定性重跑结果一致。

- [ ] **步骤 5：中文提交**

```bash
git add Packages/PokerCore/Sources/PokerCoordinator Packages/PokerCore/Tests/PokerCoordinatorTests/BotTurnSchedulerTests.swift Packages/PokerCore/Tests/PokerCoordinatorTests/CoordinatorHandPropertyTests.swift
git commit -m "feat: 接入普通桌公平机器人调度"
```

---

### 任务 6：实现动画队列、摊牌结算和保存重试

**文件：**
- 新建：`Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableAnimationMapper.swift`
- 修改：`Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableCoordinator.swift`
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorTests/TableAnimationTests.swift`
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorTests/SettlementPipelineTests.swift`

**接口：**
- 消费：`GameTransition.events`、package `pendingShowdownObservation`。
- 产出：顺序动画、`retrySave()`、`startNextHand(settings:)`。

- [ ] **步骤 1：写失败测试，锁定动画事件顺序**

```swift
@Test func 翻牌事件逐张映射且行动动画先于下一行动() throws {
    let cards = try decodeCards(
        #"[{"rank":14,"suit":3},{"rank":13,"suit":2},{"rank":7,"suit":1}]"#
    )
    let events = try CashTableAnimationMapper.map([
        .actionApplied(seat: try SeatID(2), action: .check),
        .streetChanged(.flop),
        .communityCardsDealt(cards),
    ], humanSeat: try SeatID(0), humanCards: [], beforeCommitments: [:], afterCommitments: [:])
    #expect(events.map(\.kind) == [
        .showAction, .streetChanged, .revealCommunityCard,
        .revealCommunityCard, .revealCommunityCard,
    ])
}
```

- [ ] **步骤 2：写失败测试，锁定保存失败和幂等重试**

```swift
@Test @MainActor func 保存失败停留结算且相同业务编号重试() async throws {
    let repository = FailOnceSessionRepository()
    let coordinator = try await CoordinatorScenario.pendingSettlement(repository: repository)
    await coordinator.finishSettlement()
    #expect(coordinator.state.phase == .saveFailed)
    #expect(coordinator.state.errorMessage == "牌局保存失败，请重试。")
    let firstID = try #require(await repository.attemptedBusinessIDs().first)
    try await coordinator.retrySave()
    #expect(coordinator.state.phase == .awaitingNextHand)
    #expect(await repository.attemptedBusinessIDs() == [firstID, firstID])
}
```

- [ ] **步骤 3：实现纯动画映射和串行播放**

映射规则：

```swift
case .holeCardsDealt(let seat):
    [.dealHoleCard(
        seat: seat,
        card: seat == humanSeat
            ? nextHumanCard.removeFirst()
            : .faceDown
    )]
case .blindPosted(let seat, let amount):
    [.postBlind(seat: seat, amount: amount)]
case .actionApplied(let seat, let action):
    [.showAction(seat: seat, action: action)]
case .streetChanged(let street):
    [.streetChanged(street)]
case .communityCardsDealt(let cards):
    cards.enumerated().map { .revealCommunityCard(card: $0.element, index: $0.offset) }
case .uncalledBetReturned(let seat, let amount):
    [.returnUncalledBet(seat: seat, amount: amount)]
case .potAwarded(let index, _, let amounts):
    amounts.keys.sorted().flatMap {
        [.awardPot(seat: $0, amount: amounts[$0]!, potIndex: index), .highlightWinner($0)]
    }
case .handStarted, .potCreated, .handCompleted:
    []
```

`CashTableAnimationMapper.map` 额外接收转换前后的 `[SeatID: Chips]` 街道投入快照和投影得到的真人 `[TableCardState.faceUp(Card)]` 队列。对于 `actionApplied`，先发布 `.showAction`，再用该座位转换前后投入的受检差值发布 `.moveCommitmentToPot`；差值为零时省略移动事件，负数或溢出时抛出 `chipArithmeticOverflow`。真人底牌只在真人的两次 `holeCardsDealt` 事件中依次移出，数量不为两张时抛出 `missingObservation`；机器人永远映射为 `.faceDown`。播放器逐项设置 `state.animation` 并使用注入 sleep；`reduceMotion` 时延迟为零但事件顺序不变。

- [ ] **步骤 4：实现结算、重试和下一手门禁**

进入 pending settlement 时先读取安全摊牌观察，把其中非弃牌座位的 `TableSeatState.cards` 临时替换为两张 `.faceUp` 并播放赢家高亮；已弃牌座位继续保留牌背，不读取其底牌。随后使用一次生成的业务编号调用 `commitPendingHand`。成功后进入 `.awaitingNextHand`；失败保留相同编号进入 `.saveFailed`。只有 `.awaitingNextHand` 接受 `.nextHand`，只有 `.saveFailed` 接受 `.retrySave`。

- [ ] **步骤 5：运行目标测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter TableAnimationTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter SettlementPipelineTests
```

预期：动画顺序、摊牌隐藏、失败门禁和幂等重试全部通过。

- [ ] **步骤 6：中文提交**

```bash
git add Packages/PokerCore/Sources/PokerCoordinator Packages/PokerCore/Tests/PokerCoordinatorTests/TableAnimationTests.swift Packages/PokerCore/Tests/PokerCoordinatorTests/SettlementPipelineTests.swift
git commit -m "feat: 实现牌桌动画与结算保存流程"
```

---

### 任务 7：接入唯一 LocalPokerStore、真实买入和应用生命周期

**文件：**
- 修改：`RiverClub/App/AppSession.swift`
- 修改：`RiverClub/App/RiverClubApp.swift`
- 修改：`RiverClub/App/AppRootView.swift`
- 修改：`RiverClub/Features/Lobby/BuyInSheet.swift`
- 修改：`RiverClubTests/AppSessionTests.swift`
- 修改：`RiverClubTests/BuyInTests.swift`
- 新建：`RiverClubTests/CashTableEntryTests.swift`
- 修改：`project.yml`

**接口：**
- 消费：`LocalPokerStore`、`CashTableCoordinator`、`CashTableRequest`。
- 产出：真实 `chipBalance`、原子买入、当前 `tableCoordinator`。

- [ ] **步骤 1：写失败测试，修正 40–100BB 买入范围**

```swift
func testBuyInUsesFortyToOneHundredBigBlinds() {
    let range = BuyInRange(bigBlind: 400, balance: 128_500)
    XCTAssertEqual(range.minimum, 16_000)
    XCTAssertEqual(range.maximum, 40_000)
}
```

- [ ] **步骤 2：写失败测试，验证买入失败不扣余额不进桌**

```swift
@MainActor
func testFailedSitDownKeepsBalanceAndRoute() throws {
    let fixture = try AppSessionFixture(failingSave: true)
    let before = fixture.session.chipBalance
    XCTAssertThrowsError(
        try fixture.session.joinCashTable(
            fixture.table,
            buyIn: 16_000,
            autoTopUp: false
        )
    )
    XCTAssertEqual(fixture.session.chipBalance, before)
    XCTAssertEqual(fixture.session.route, .lobby)
    XCTAssertNil(fixture.session.tableCoordinator)
}
```

- [ ] **步骤 3：运行测试确认失败**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubTests/BuyInTests -only-testing:RiverClubTests/CashTableEntryTests CODE_SIGNING_ALLOWED=NO
```

预期：范围仍为 10–50BB，且 `joinCashTable` 尚不存在。

- [ ] **步骤 4：实现 AppSession 唯一存储和真实余额**

```swift
@MainActor @Observable
final class AppSession {
    @ObservationIgnored let pokerStore: LocalPokerStore
    private(set) var tableCoordinator: CashTableCoordinator?
    var chipBalance: Int { pokerStore.accountBalance.rawValue }

    init(
        pokerStore: LocalPokerStore,
        botSettingsRepository: any BotSettingsPersisting
    ) {
        self.pokerStore = pokerStore
        self.botSettingsRepository = botSettingsRepository
        botSettings = (try? botSettingsRepository.load()) ?? .recommended
    }

    static func live() throws -> AppSession {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("RiverClub", isDirectory: true)
        let store = try LocalPokerStore.open(
            directory: support.appendingPathComponent("PokerSession", isDirectory: true),
            clock: AppSessionClock()
        )
        return try AppSession(
            pokerStore: store,
            botSettingsRepository: BotSettingsRepository.applicationSupport()
        )
    }

    func joinCashTable(
        _ table: PokerTableSummary,
        buyIn: Int,
        autoTopUp: Bool
    ) throws {
        let request = try CashTableRequestFactory.make(table: table, buyIn: buyIn)
        _ = try pokerStore.sitDown(
            request: request,
            businessID: try BusinessID("sit-down:\(request.sessionID.rawValue)")
        )
        tableCoordinator = CashTableCoordinator(
            store: pokerStore,
            humanSeat: request.humanSeat,
            seatProfiles: TableSeatProfileFactory.make(humanSeat: request.humanSeat)
        )
        tableState.enter(table)
        route = .table
    }
}
```

`AppSessionClock` 实现 `SessionClock`，从系统 `Date` 和当前日历生成 `LocalDay`。删除无存储的 `AppSession()` 默认初始化；现有测试全部改为通过 `AppSessionFixture` 注入临时目录存储和 `FixedSessionClock`。

`TableSeatProfileFactory` 固定生成一个真人昵称和八个本地机器人昵称，座位编号与 `CashTableRequestFactory` 完全一致；它只提供展示身份，不包含牌、决策规则或筹码。`CashTableEntryTests` 增加九个资料唯一且与请求座位集合相等的断言。

`RiverClubApp` 在 `init` 中用 `try AppSession.live()` 初始化可选 `@State`。成功显示 `AppRootView`；失败显示独立的 `PersistenceStartupErrorView`，文案为“牌局数据无法打开，请重新启动应用。”，此状态不提供买入或进入牌桌入口，绝不回退到内存余额。

- [ ] **步骤 5：修正买入范围和 AppRootView 流程**

增加：

```swift
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
```

删除 `session.chipBalance -= amount`。买入确认调用 `joinCashTable`，只有成功才关闭面板；失败在买入面板显示中文可重试错误。成功后以 `Task` 调用协调器 `startHand(settings: session.freezeBotSettingsForNextHand())`。

- [ ] **步骤 6：更新依赖并生成工程**

在应用和测试 target 增加：

```yaml
- package: PokerCore
  product: PokerCoordinator
```

运行：

```bash
xcodegen generate
```

- [ ] **步骤 7：运行应用目标测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubTests/BuyInTests -only-testing:RiverClubTests/CashTableEntryTests CODE_SIGNING_ALLOWED=NO
```

预期：40–100BB、真实余额和失败事务测试通过。

- [ ] **步骤 8：中文提交**

```bash
git add RiverClub/App RiverClub/Features/Lobby RiverClubTests project.yml
git commit -m "feat: 接入普通桌真实买入与应用会话"
```

---

### 任务 8：把静态 SwiftUI 牌桌替换为真实安全状态

**文件：**
- 修改：`RiverClub/Features/Table/PokerTableView.swift`
- 修改：`RiverClub/Features/Table/BetControlBar.swift`
- 修改：`RiverClub/Features/Table/PokerSeatView.swift`
- 新建：`RiverClub/Features/Table/TableCardView.swift`
- 新建：`RiverClub/Features/Table/TableErrorPanel.swift`
- 修改：`RiverClubTests/PokerTableLayoutTests.swift`
- 新建：`RiverClubTests/BetControlBarTests.swift`
- 修改：`RiverClubUITests/CoreFlowUITests.swift`

**接口：**
- 消费：`CashTableCoordinator.state`、`TableIntent`。
- 产出：真实九人桌、动态按钮、动画和错误重试 UI。

- [ ] **步骤 1：写失败测试，锁定动态按钮文案和金额范围**

```swift
func testRaisePresentationTurnsMaximumIntoAllIn() throws {
    let aggressive = TableAggressiveAction.raise(
        minimum: try Chips(600),
        maximum: try Chips(2_000),
        canAllIn: true
    )
    XCTAssertEqual(
        BetControlPresentation.title(for: aggressive, amount: try Chips(2_000)),
        "全下"
    )
    XCTAssertEqual(
        BetControlPresentation.title(for: aggressive, amount: try Chips(1_000)),
        "加注 1,000"
    )
}
```

- [ ] **步骤 2：运行测试确认静态控件失败**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubTests/BetControlBarTests CODE_SIGNING_ALLOWED=NO
```

- [ ] **步骤 3：重写 BetControlBar 为状态驱动**

```swift
struct BetControlBar: View {
    let controls: TableActionControls
    let onIntent: (TableIntent) -> Void
    @State private var aggressiveAmount: Int

    var body: some View {
        VStack {
            if let aggressive = controls.aggressive {
                aggressiveSlider(for: aggressive)
            }
            HStack {
                if controls.canFold { actionButton("弃牌") { onIntent(.fold) } }
                if let middle = controls.middle {
                    actionButton(BetControlPresentation.title(for: middle)) {
                        onIntent(.middle)
                    }
                }
                if let aggressive = controls.aggressive {
                    actionButton(BetControlPresentation.title(
                        for: aggressive,
                        amount: Chips(rawValue: aggressiveAmount)!
                    )) {
                        onIntent(.aggressive(amount: Chips(rawValue: aggressiveAmount)!))
                    }
                }
            }
        }
    }
}
```

预设半池、四分之三池必须先裁剪到合法范围；若裁剪后重复或等于最小值，只显示唯一有效预设。

- [ ] **步骤 4：重写 PokerTableView 和座位卡**

`PokerTableView` 接收 `@Bindable var coordinator: CashTableCoordinator`。删除 `AppRootView` 中的 `tableSeatState`、`loadTableSeats()` 以及进入牌桌后的第二套 `repository.seats()` 加载；删除静态公共牌、底池 3,600、固定行动者和固定跟注金额，统一使用 `state.seats`、`state.communityCards`、`state.pot`、`state.controls`、`state.secondsRemaining`。真人两张 `.faceUp` 显示牌面，机器人 `.faceDown` 显示牌背。

阶段 UI：

- `.waitingForHuman`：显示动态 `BetControlBar`。
- `.botThinking`：显示“思考中”。
- `.awaitingNextHand`：显示“下一手”。
- `.saveFailed`：显示 `TableErrorPanel` 和“重试保存”。
- 其他阶段：隐藏操作按钮并显示对应状态文案。

- [ ] **步骤 5：实现基础动画消费和减少动态效果**

SwiftUI 根据 `state.animation` 使用 `withAnimation` 更新展示；`.dealHoleCard`、`.revealCommunityCard`、`.awardPot` 和 `.highlightWinner` 提供缩放/位移动画。读取 `accessibilityReduceMotion`，开启时使用 `.identity` 或零时长，但不改变协调器事件顺序。

- [ ] **步骤 6：更新 UI 测试路径**

`CoreFlowUITests`：登录 → 选择桌 → 选择至少 40BB → 确认买入 → 等待 `table.safeCanvas` → 验证九座、真人底牌和当前动态操作区 → 使用确定性 UI 测试启动参数完成一手 → 点击 `action.nextHand`。

- [ ] **步骤 7：运行单元和 UI 测试**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubTests/BetControlBarTests -only-testing:RiverClubTests/PokerTableLayoutTests CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubUITests/CoreFlowUITests CODE_SIGNING_ALLOWED=NO
```

预期：动态控件、九座布局和完整一手 UI 路径通过。

- [ ] **步骤 8：中文提交**

```bash
git add RiverClub/Features/Table RiverClubTests RiverClubUITests
git commit -m "feat: 将横屏牌桌接入真实牌局状态"
```

---

### 任务 9：加固公开边界、后台暂停和最终集成验收

**文件：**
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorPublicAPITests/PokerCoordinatorPublicAPITests.swift`
- 新建：`Packages/PokerCore/Tests/PokerCoordinatorTests/CoordinatorLifecycleTests.swift`
- 修改：`RiverClubTests/PokerSessionImportTests.swift`
- 修改：`project.yml`

**接口：**
- 消费：任务 1–8 的公开接口。
- 产出：可供 RiverClub 稳定使用的第一版普通桌闭环。

- [ ] **步骤 1：增加隐藏信息负向编译探针**

沿用 `PokerBotPublicAPITests` 的临时 Swift 源码 typecheck 方式，逐项确认普通 `import PokerCoordinator` 无法编译以下访问：

```swift
_ = tableState.deck
_ = tableState.seed
_ = tableState.checkpoint
_ = tableState.opponentHoleCards
_ = coordinator.playerObservation(for: SeatID(rawValue: 1)!)
_ = coordinator.pendingShowdownObservation
```

每个探针必须失败于“无成员”或“不可访问”，不能失败于找不到模块。

- [ ] **步骤 2：增加后台暂停和前台恢复测试**

```swift
@Test @MainActor func 后台取消计时与机器人且前台只恢复当前行动() async throws {
    let fixture = try await CoordinatorScenario.botThinking()
    await fixture.coordinator.suspend()
    let actionCount = try fixture.actionCount()
    #expect(fixture.coordinator.state.phase == .suspended)
    #expect(await fixture.botService.cancelCount == 1)
    await fixture.clock.advance(by: .seconds(60))
    #expect(try fixture.actionCount() == actionCount)
    try await fixture.coordinator.resume()
    #expect(fixture.coordinator.state.stateVersion > fixture.versionBeforeSuspend)
    #expect(await fixture.botService.maximumConcurrentCalls() == 1)
}
```

- [ ] **步骤 3：运行全部 Swift Package 测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore
```

预期：现有规则、会话、机器人和新增协调器测试全部通过；0 个失败。

- [ ] **步骤 4：重新生成工程并执行通用 iOS 测试构建**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

预期：日志包含 `TEST BUILD SUCCEEDED`。

- [ ] **步骤 5：执行 RiverClub 单元测试和核心 UI 测试**

先用 `xcrun simctl list devices available` 确认本机当前的 iPhone 17 Pro Max（iOS 26.5）设备 `86B6F41B-B5EA-4267-8FA3-0C92481DE8E8` 仍可用，再运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubTests CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubUITests/CoreFlowUITests CODE_SIGNING_ALLOWED=NO
```

预期：全部通过。若该 UDID 已失效，只允许从同一条 `simctl` 输出中替换为实际可用的最新 Pro Max UDID，并在交付说明中记录替换值；本机没有 iPhone 16 Pro Max，因此保留最终 iPhone 16 Pro Max 真机视觉验收项。

- [ ] **步骤 6：检查差异和独立复审**

```bash
git diff --check
git status --short
```

逐项复审：隐藏信息边界、筹码守恒、单机器人任务、超时单次触发、存档失败门禁、40–100BB 和下一手设置冻结。修正所有 Critical/Important 后重新运行步骤 3–5。

- [ ] **步骤 7：中文提交最终验收加固**

```bash
git add Packages/PokerCore/Tests/PokerCoordinatorPublicAPITests Packages/PokerCore/Tests/PokerCoordinatorTests RiverClubTests RiverClubUITests project.yml
git commit -m "test: 验证普通桌可玩闭环与安全边界"
```

## 最终交付证据

交付时必须报告：

- Swift Package 测试总数和失败数。
- RiverClub 单元测试与 UI 测试结果。
- 通用 iOS `build-for-testing` 结果。
- 实际使用的 Pro Max 模拟器型号。
- 从买入、自动发牌、真人/机器人行动、结算保存到下一手的端到端结果。
- `git status --short` 为空，以及所有新增 Git 提交均为中文。
