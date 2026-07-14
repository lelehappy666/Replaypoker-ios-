# River Club 公平机器人系统实施计划

> **面向智能代理：** 必须逐任务使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 执行；每一步用复选框跟踪。

**目标：** 实现不能读取隐藏信息、支持三档难度、四种模型、高级参数和困难模式蒙特卡洛估算的可复现本地机器人系统。

**架构：** 在现有 Swift Package 中新增只依赖 `PokerCore` 的 `PokerBot` 产品。机器人只消费从 `PlayerObservation` 构造的安全观察；纯规则评分、可注入模拟器和决策组合彼此隔离，应用层负责设置持久化和后续协调器接入。

**技术栈：** Swift 6、Swift Package Manager、Swift Testing、Codable、Swift Concurrency、XcodeGen、iOS 18。

## 全局约束

- 所有文档、规格、计划、交付说明和新 Git/GitHub 提交必须使用中文。
- `PokerBot` 不能接受其他玩家底牌、牌堆、洗牌种子、检查点或完整内部牌局状态。
- 简单和标准模式不得运行蒙特卡洛模拟；困难模式快速、标准、自然分别运行 800、2,000、5,000 次。
- 相同观察、设置、机器人身份和决策种子必须得到相同结果。
- 设置在一手开始时冻结，修改从下一手生效。
- 机器人只能从 `PokerCore` 提供的合法动作集合中选择；失败时能过牌则过牌，否则弃牌。
- 不引入第三方依赖、网络请求、外部模型或在线策略服务。

---

### 任务 1：模块、公平观察与设置基础

**文件：**
- 修改：`Packages/PokerCore/Package.swift`
- 新建：`Packages/PokerCore/Sources/PokerBot/Domain/BotSettings.swift`
- 新建：`Packages/PokerCore/Sources/PokerBot/Domain/BotObservation.swift`
- 新建：`Packages/PokerCore/Sources/PokerBot/Domain/BotPersonality.swift`
- 新建：`Packages/PokerCore/Tests/PokerBotTests/BotSettingsTests.swift`
- 新建：`Packages/PokerCore/Tests/PokerBotTests/BotObservationTests.swift`
- 新建：`Packages/PokerCore/Tests/PokerBotPublicAPITests/PokerBotPublicAPITests.swift`

**接口：**
- 消费：`PokerCore.PlayerObservation`、`PublicSeat`、`LegalActionSet`、`RecordedAction`。
- 产出：`BotSettings`、`BotObservation`、`BotPersonality.offsets(for:schemaVersion:)`。

- [ ] **步骤 1：编写失败测试**

```swift
@Test func recommendedSettingsMatchSpecification() throws {
    let settings = BotSettings.recommended
    #expect(settings.difficulty == .standard)
    #expect(settings.model == .balanced)
    #expect(settings.aggression == 50)
    #expect(settings.bluffFrequency == 30)
    #expect(settings.callingWidth == 50)
    #expect(settings.betSizing == 50)
    #expect(settings.thinkingSpeed == .standard)
    #expect(settings.analyzesHistory)
}

@Test func personalityOffsetsAreStableAndBounded() {
    let first = BotPersonality.offsets(for: "bot-7", schemaVersion: 1)
    let second = BotPersonality.offsets(for: "bot-7", schemaVersion: 1)
    #expect(first == second)
    #expect(first.values.allSatisfy { (-5...5).contains($0) })
}
```

- [ ] **步骤 2：运行测试并确认因模块不存在而失败**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PokerBotTests
```

预期：失败，提示找不到 `PokerBot` 或相关类型。

- [ ] **步骤 3：建立产品、目标和受检设置值对象**

```swift
public struct BotSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let recommended = try! BotSettings(
        difficulty: .standard, model: .balanced,
        aggression: 50, bluffFrequency: 30,
        callingWidth: 50, betSizing: 50,
        thinkingSpeed: .standard, analyzesHistory: true
    )

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        difficulty: BotDifficulty,
        model: BotModel,
        aggression: Int,
        bluffFrequency: Int,
        callingWidth: Int,
        betSizing: Int,
        thinkingSpeed: BotThinkingSpeed,
        analyzesHistory: Bool
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              [aggression, bluffFrequency, callingWidth, betSizing]
                .allSatisfy({ (0...100).contains($0) })
        else { throw BotError.invalidSettings }
        // 保存已验证字段
    }
}
```

- [ ] **步骤 4：实现安全观察和稳定偏移**

```swift
public struct BotObservation: Codable, Equatable, Sendable {
    public let handID: String
    public let stateVersion: Int
    public let viewer: SeatID
    public let ownHoleCards: [Card]
    public let communityCards: [Card]
    public let publicSeats: [PublicSeat]
    public let currentActor: SeatID?
    public let street: Street
    public let currentBet: Chips
    public let legalActions: LegalActionSet
    public let actions: [RecordedAction]

    public init(handID: String, stateVersion: Int, observation: PlayerObservation) throws {
        guard !handID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              stateVersion >= 0,
              observation.currentActor == observation.viewer,
              let legalActions = observation.legalActions
        else { throw BotError.invalidObservation }
        // 仅复制 PlayerObservation 已公开字段
    }
}
```

- [ ] **步骤 5：添加公开 API 负向编译探针**

测试使用临时 Swift 文件验证 `PokerBot` 无法构造带牌堆、对手底牌或种子的观察，也不能导入包内实现类型。

- [ ] **步骤 6：运行定向与完整测试**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PokerBot
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

预期：全部通过。

- [ ] **步骤 7：中文提交**

```bash
git add Packages/PokerCore/Package.swift Packages/PokerCore/Sources/PokerBot Packages/PokerCore/Tests/PokerBotTests Packages/PokerCore/Tests/PokerBotPublicAPITests
git commit -m "feat: 建立公平机器人观察与设置基础"
```

### 任务 2：规则评分与候选动作

**文件：**
- 新建：`Packages/PokerCore/Sources/PokerBot/Strategy/RuleBasedEvaluator.swift`
- 新建：`Packages/PokerCore/Sources/PokerBot/Strategy/ActionCandidate.swift`
- 新建：`Packages/PokerCore/Sources/PokerBot/Strategy/PreflopRange.swift`
- 新建：`Packages/PokerCore/Tests/PokerBotTests/RuleBasedEvaluatorTests.swift`

**接口：**
- 消费：`BotObservation`、`BotSettings`、`BotPersonalityOffsets`。
- 产出：`RuleEvaluation` 和仅由合法动作生成的 `[ActionCandidate]`。

- [ ] **步骤 1：测试简单模式只使用牌力和位置，标准模式增加赔率与牌面结构**

```swift
@Test func simpleAndStandardUseDifferentFeatureSets() throws {
    let simple = try RuleBasedEvaluator().evaluate(fixture, settings: .simpleFixture)
    let standard = try RuleBasedEvaluator().evaluate(fixture, settings: .standardFixture)
    #expect(simple.features.contains(.madeHandStrength))
    #expect(!simple.features.contains(.potOdds))
    #expect(standard.features.contains(.potOdds))
}
```

- [ ] **步骤 2：运行定向测试确认失败**

运行：`swift test --filter RuleBasedEvaluatorTests`  
预期：因评分器不存在而失败。

- [ ] **步骤 3：实现起手牌分组、位置、成牌、听牌、底池赔率和有效筹码评分**

评分全部使用整数基点，避免浮点比较导致不可复现；所有加减乘法使用溢出检查。

- [ ] **步骤 4：只从 `LegalActionSet` 构造 fold、check、call、bet、raiseTo、allIn 候选**

```swift
static func legalCandidates(from legal: LegalActionSet) -> [ActionCandidate] {
    // 每个候选都直接对应 legal 中已存在的能力或金额范围
}
```

- [ ] **步骤 5：添加边界和随机合法观察测试并运行完整测试**

运行：`swift test --filter RuleBasedEvaluatorTests && swift test`  
预期：全部通过。

- [ ] **步骤 6：中文提交**

```bash
git add Packages/PokerCore/Sources/PokerBot/Strategy Packages/PokerCore/Tests/PokerBotTests
git commit -m "feat: 实现机器人规则评分与合法候选"
```

### 任务 3：可复现蒙特卡洛权益估算

**文件：**
- 新建：`Packages/PokerCore/Sources/PokerBot/Simulation/MonteCarloEstimator.swift`
- 新建：`Packages/PokerCore/Sources/PokerBot/Simulation/UnknownCardSampler.swift`
- 新建：`Packages/PokerCore/Tests/PokerBotTests/MonteCarloEstimatorTests.swift`
- 新建：`Packages/PokerCore/Tests/PokerBotTests/MonteCarloPerformanceTests.swift`

**接口：**
- 消费：`BotObservation`、对手数量、`UInt64` 决策种子和模拟次数。
- 产出：`EquityEstimate(winBasisPoints:tieBasisPoints:effectiveBasisPoints:iterations:)`。

- [ ] **步骤 1：测试采样不重复已知牌且相同种子结果一致**

```swift
@Test func samplingNeverRepeatsKnownCardsAndIsDeterministic() async throws {
    let first = try await estimator.estimate(observation, iterations: 800, seed: 42)
    let second = try await estimator.estimate(observation, iterations: 800, seed: 42)
    #expect(first == second)
    #expect(first.iterations == 800)
}
```

- [ ] **步骤 2：确认测试失败后实现未知牌集合和 Fisher–Yates 确定性采样**

- [ ] **步骤 3：用 `HandEvaluator` 比较机器人与存活对手的七张牌权益**

- [ ] **步骤 4：每批模拟检查任务取消；任何重复牌或不可能牌数抛出 `invalidObservation`**

- [ ] **步骤 5：验证 800、2,000、5,000 次、取消和性能记录**

运行：`swift test --filter MonteCarlo`  
预期：正确性与性能记录测试通过。

- [ ] **步骤 6：完整测试并中文提交**

```bash
swift test
git add Packages/PokerCore/Sources/PokerBot/Simulation Packages/PokerCore/Tests/PokerBotTests
git commit -m "feat: 实现困难机器人权益模拟"
```

### 任务 4：难度、模型和高级参数决策组合

**文件：**
- 新建：`Packages/PokerCore/Sources/PokerBot/Decision/BotDecision.swift`
- 新建：`Packages/PokerCore/Sources/PokerBot/Decision/BotDecisionEngine.swift`
- 新建：`Packages/PokerCore/Sources/PokerBot/History/BotHistorySummary.swift`
- 新建：`Packages/PokerCore/Tests/PokerBotTests/BotDecisionEngineTests.swift`
- 新建：`Packages/PokerCore/Tests/PokerBotTests/BotDecisionPropertyTests.swift`

**接口：**
- 消费：观察、设置、身份、种子、可选历史摘要和可注入 `EquityEstimating`。
- 产出：包含 `PlayerAction`、状态版本、理由码和模拟次数的 `BotDecision`。

- [ ] **步骤 1：测试三档难度的模拟调用次数和四种模型权重方向**

- [ ] **步骤 2：测试 0、推荐值、100 参数边界仍只返回合法动作**

- [ ] **步骤 3：实现模型权重、参数权重、偏移应用和确定性加权选择**

- [ ] **步骤 4：困难模式按思考档调用 800、2,000、5,000 次；其他难度不调用模拟器**

- [ ] **步骤 5：历史关闭时拒绝读取摘要，自适应无样本时退化为均衡型**

- [ ] **步骤 6：运行 1,000 组随机合法观察属性测试与完整测试**

运行：`swift test --filter BotDecision && swift test`  
预期：所有动作合法且可复现。

- [ ] **步骤 7：中文提交**

```bash
git add Packages/PokerCore/Sources/PokerBot/Decision Packages/PokerCore/Sources/PokerBot/History Packages/PokerCore/Tests/PokerBotTests
git commit -m "feat: 组合机器人难度模型与高级参数"
```

### 任务 5：异步决策、取消、超时和保底动作

**文件：**
- 新建：`Packages/PokerCore/Sources/PokerBot/Decision/BotDecisionService.swift`
- 新建：`Packages/PokerCore/Tests/PokerBotTests/BotDecisionServiceTests.swift`

**接口：**
- 消费：`BotDecisionRequest`、超时时钟和决策引擎。
- 产出：可取消的异步 `decide(_:)`，结果带 handID/stateVersion。

- [ ] **步骤 1：测试状态过期、显式取消、超时和引擎错误均不提交旧动作**

- [ ] **步骤 2：实现结构化并发任务组竞争决策与超时**

- [ ] **步骤 3：实现 `FallbackAction.choose(from:)`：能过牌则过牌，否则弃牌**

- [ ] **步骤 4：测试展示延迟由种子稳定派生且位于对应时间范围**

- [ ] **步骤 5：运行并发压力测试、完整测试并中文提交**

```bash
swift test --filter BotDecisionServiceTests
swift test
git add Packages/PokerCore/Sources/PokerBot/Decision Packages/PokerCore/Tests/PokerBotTests
git commit -m "feat: 实现机器人异步决策与安全降级"
```

### 任务 6：设置持久化与应用层接口

**文件：**
- 新建：`RiverClub/Features/Settings/BotSettingsEditor.swift`
- 新建：`RiverClub/Services/BotSettingsRepository.swift`
- 新建：`RiverClubTests/BotSettingsRepositoryTests.swift`
- 修改：`RiverClub/App/AppSession.swift`
- 修改：`project.yml`

**接口：**
- 消费：`PokerBot.BotSettings`。
- 产出：`load()`、`save(_:)`、`restoreRecommended()` 和一手级冻结快照接口。

- [ ] **步骤 1：测试首次打开、保存重开、损坏文件和失败写入不覆盖旧设置**

- [ ] **步骤 2：实现应用支持目录内临时文件、同步和原子替换**

- [ ] **步骤 3：实现编辑草稿与确认保存；恢复推荐设置必须显式确认**

- [ ] **步骤 4：在 `AppSession` 保存当前设置和 `freezeBotSettingsForNextHand()` 快照**

- [ ] **步骤 5：运行 RiverClub 单元测试和 iOS 通用设备构建**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

预期：`TEST BUILD SUCCEEDED`。

- [ ] **步骤 6：中文提交**

```bash
git add RiverClub/Features/Settings RiverClub/Services/BotSettingsRepository.swift RiverClub/App/AppSession.swift RiverClubTests/BotSettingsRepositoryTests.swift project.yml
git commit -m "feat: 持久化机器人全局设置"
```

### 任务 7：最终边界、性能和集成验收

**文件：**
- 修改：`Packages/PokerCore/Tests/PokerBotPublicAPITests/PokerBotPublicAPITests.swift`
- 修改：`Packages/PokerCore/Tests/PokerBotTests/BotDecisionPropertyTests.swift`
- 修改：`Packages/PokerCore/Tests/PokerBotTests/MonteCarloPerformanceTests.swift`
- 修改：`RiverClubTests/BotSettingsRepositoryTests.swift`

**接口：**
- 消费：任务 1–6 的公开接口。
- 产出：机器人子项目可供普通桌协调器接入的稳定发布边界。

- [ ] **步骤 1：验证普通导入无法读取牌堆、检查点、种子和其他座位底牌**

- [ ] **步骤 2：运行公平性负向编译探针、1,000 观察属性测试和三档模拟性能测试**

- [ ] **步骤 3：运行全部 Swift Package 测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

预期：全部通过。

- [ ] **步骤 4：重新生成工程并执行 iOS 通用设备构建**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

预期：`TEST BUILD SUCCEEDED`。

- [ ] **步骤 5：检查差异、独立复审并修正 Critical/Important**

```bash
git diff --check
git status --short
```

- [ ] **步骤 6：中文提交最终测试加固**

```bash
git add Packages/PokerCore/Tests/PokerBotPublicAPITests Packages/PokerCore/Tests/PokerBotTests RiverClubTests/BotSettingsRepositoryTests.swift
git commit -m "test: 加固机器人公平性与性能边界"
```

完成后单独设计并实施“普通桌 SwiftUI 可玩闭环”。
