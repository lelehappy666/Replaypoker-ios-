# River Club 普通桌会话、娱乐筹码账本与原子存档实施计划

> **供智能代理执行：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按任务逐项实施。本计划使用复选框追踪步骤。

**目标：** 在现有 PokerCore 之上实现可恢复、可审计、幂等的本地普通桌会话、娱乐筹码账本和原子文件存档。

**架构：** 在 `Packages/PokerCore` Swift Package 内新增独立 `PokerSession` target/product。PokerCore 通过 Swift `package` 访问级别向 PokerSession 提供经过验证的完整恢复快照；应用和机器人只能使用 PokerSession 的安全观察与业务门面。所有业务命令先修改内存副本，原子写入成功后才替换已提交状态。

**技术栈：** Swift 6、Swift Package Manager、Swift Testing、Foundation Codable、JSON 文件、XcodeGen、iOS 18。

## 全局约束

- 所有说明文档、规格、实施计划和交付说明使用中文。
- 所有新 Git/GitHub 提交信息使用中文；允许英文类型前缀，但冒号后的标题和正文必须为中文。
- 直接在 `main` 实施，不创建 worktree。
- 不引入第三方依赖，不依赖 SwiftUI、UIKit、数据库框架或系统单例。
- 账户初始娱乐筹码为 128,500；普通桌买入范围为 40–100 个大盲。
- 每日赠送为 10,000，每个设备自然日最多一次。
- 余额低于 2,000 且没有未结算买入时，破产救济补足至 20,000，每个设备自然日最多一次。
- 普通桌固定九人，一个真人座位和八个外部驱动座位；本计划不实现机器人策略。
- 进行中隐藏状态不能出现在 public API、普通历史查询、脱敏事件或日志中。
- 每个生产任务必须先得到失败测试，再写最小实现；每项完成后独立代码审查。
- 完整包测试命令使用显式 Xcode 工具链和 `/tmp` 缓存，并保留现有 500 种子属性测试。

---

## 文件结构

```text
Packages/PokerCore/
├── Package.swift
├── Sources/PokerCore/Game/HoldemCheckpoint.swift
├── Sources/PokerSession/
│   ├── Domain/SessionPrimitives.swift
│   ├── Economy/EntertainmentChipLedger.swift
│   ├── Cash/CashGameSession.swift
│   ├── Persistence/PersistedAppState.swift
│   ├── Persistence/FileSessionRepository.swift
│   ├── Store/LocalPokerStore.swift
│   └── History/HandHistory.swift
├── Tests/PokerCoreTests/HoldemCheckpointTests.swift
├── Tests/PokerCorePublicAPITests/HoldemCheckpointBoundaryTests.swift
├── Tests/PokerSessionTests/
└── Tests/PokerSessionPublicAPITests/
```

`PokerSession` 中包含隐藏恢复数据的类型使用 `package` 或 `internal`，不遵循公开协议；应用只取得 `LocalPokerStore`、安全观察、脱敏转换、账本视图和已完成记录。

---

### 任务 1：建立 PokerSession target、领域标识与可注入时间

**文件：**

- 修改：`Packages/PokerCore/Package.swift`
- 创建：`Packages/PokerCore/Sources/PokerSession/Domain/SessionPrimitives.swift`
- 创建：`Packages/PokerCore/Tests/PokerSessionTests/SessionPrimitivesTests.swift`

**接口：**

- 输入：PokerCore 的 `Chips`、`SeatID` 和 `HandConfig`。
- 产出：`BusinessID`、`SessionID`、`HandID`、`TableID`、`LocalDay`、`SessionClock`、`SessionEconomy`、`PokerSessionError`。

- [ ] **步骤 1：先写 Package 与基础类型失败测试**

```swift
import Foundation
import Testing
@testable import PokerSession

@Test func economyConstantsMatchApprovedDesign() throws {
    #expect(SessionEconomy.initialBalance == try Chips(128_500))
    #expect(SessionEconomy.dailyGift == try Chips(10_000))
    #expect(SessionEconomy.reliefThreshold == try Chips(2_000))
    #expect(SessionEconomy.reliefTarget == try Chips(20_000))
    #expect(SessionEconomy.minimumBuyInBigBlinds == 40)
    #expect(SessionEconomy.maximumBuyInBigBlinds == 100)
}

@Test func identifiersRejectEmptyOrWhitespaceValues() {
    #expect(throws: PokerSessionError.invalidIdentifier) { try BusinessID("  ") }
    #expect(throws: PokerSessionError.invalidIdentifier) { try HandID("") }
}

@Test func fixedClockProvidesStableMomentAndLocalDay() throws {
    let instant = Date(timeIntervalSince1970: 1_720_915_200)
    let clock = FixedSessionClock(now: instant, day: try LocalDay("2026-07-14"))
    #expect(clock.now == instant)
    #expect(clock.currentDay == try LocalDay("2026-07-14"))
}
```

- [ ] **步骤 2：运行测试并确认 RED**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/riverclub-session-task1-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/riverclub-session-task1-clang-cache \
swift test --disable-sandbox --package-path Packages/PokerCore --filter SessionPrimitivesTests
```

预期：编译失败，提示找不到 `PokerSession` target 或上述基础类型。

- [ ] **步骤 3：增加 target/product 与最小基础类型**

`Package.swift` 增加：

```swift
.library(name: "PokerSession", targets: ["PokerSession"]),
```

以及：

```swift
.target(name: "PokerSession", dependencies: ["PokerCore"]),
.testTarget(name: "PokerSessionTests", dependencies: ["PokerSession", "PokerCore"]),
.testTarget(name: "PokerSessionPublicAPITests", dependencies: ["PokerSession", "PokerCore"]),
```

`SessionPrimitives.swift` 定义：

```swift
import Foundation
import PokerCore

public enum PokerSessionError: Error, Equatable, Sendable {
    case invalidIdentifier
    case chipArithmeticOverflow
    case insufficientBalance
    case businessIDConflict
    case dailyGiftAlreadyClaimed
    case reliefNotAvailable
    case invalidBuyIn
    case invalidTable
    case invalidLifecycle
    case handNotComplete
    case settlementPending
    case unsupportedVersion(Int)
    case corruptSnapshot
    case persistenceFailed
    case recordNotFound
}

public protocol SessionIdentifier: Codable, Hashable, Sendable {
    var rawValue: String { get }
    init(_ rawValue: String) throws
}

public extension SessionIdentifier {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do { self = try Self(container.decode(String.self)) }
        catch {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid session identifier"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct BusinessID: SessionIdentifier {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PokerSessionError.invalidIdentifier }
        self.rawValue = value
    }
}

public struct SessionID: SessionIdentifier {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PokerSessionError.invalidIdentifier }
        self.rawValue = value
    }
}

public struct HandID: SessionIdentifier {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PokerSessionError.invalidIdentifier }
        self.rawValue = value
    }
}

public struct TableID: SessionIdentifier {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PokerSessionError.invalidIdentifier }
        self.rawValue = value
    }
}

public struct LocalDay: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) throws {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            throw PokerSessionError.invalidIdentifier
        }
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            throw PokerSessionError.invalidIdentifier
        }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard components.year == year, components.month == month, components.day == day else {
            throw PokerSessionError.invalidIdentifier
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do { self = try Self(container.decode(String.self)) }
        catch {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid local day"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public protocol SessionClock: Sendable {
    var now: Date { get }
    var currentDay: LocalDay { get }
}

public struct FixedSessionClock: SessionClock {
    public let now: Date
    public let currentDay: LocalDay
    public init(now: Date, day: LocalDay) {
        self.now = now
        currentDay = day
    }
}

public enum SessionEconomy {
    public static let initialBalance = Chips(rawValue: 128_500)!
    public static let dailyGift = Chips(rawValue: 10_000)!
    public static let reliefThreshold = Chips(rawValue: 2_000)!
    public static let reliefTarget = Chips(rawValue: 20_000)!
    public static let minimumBuyInBigBlinds = 40
    public static let maximumBuyInBigBlinds = 100
}
```

以上协议默认实现确保每个标识使用单值 Codable，解码时重新调用验证构造器并拒绝空字符串。

- [ ] **步骤 4：运行定向与全量测试**

预期：基础类型测试全部通过，现有 PokerCore 138 项测试保持通过。

- [ ] **步骤 5：提交任务 1**

```bash
git add Packages/PokerCore
git commit -m "feat: 建立普通桌会话基础模块"
```

---

### 任务 2：实现娱乐筹码账本和幂等流水

**文件：**

- 创建：`Packages/PokerCore/Sources/PokerSession/Economy/EntertainmentChipLedger.swift`
- 创建：`Packages/PokerCore/Tests/PokerSessionTests/EntertainmentChipLedgerTests.swift`

**接口：**

- 输入：任务 1 的业务编号、自然日、时间和经济常量。
- 产出：`LedgerReason`、`LedgerEntry`、`EntertainmentChipLedger` 及买入、退回、每日赠送、救济方法。

- [ ] **步骤 1：写账本失败测试**

```swift
@Test func buyInAndCashOutCreateAuditableEntries() throws {
    var ledger = EntertainmentChipLedger()
    let table = try TableID("jade")
    let bought = try ledger.buyIn(
        amount: try Chips(5_000), table: table,
        id: try BusinessID("buy-1"), at: .init(timeIntervalSince1970: 1)
    )
    #expect(bought.balanceBefore == try Chips(128_500))
    #expect(bought.delta == -5_000)
    #expect(ledger.balance == try Chips(123_500))

    let returned = try ledger.cashOut(
        amount: try Chips(6_250), table: table,
        id: try BusinessID("out-1"), at: .init(timeIntervalSince1970: 2)
    )
    #expect(returned.delta == 6_250)
    #expect(ledger.balance == try Chips(129_750))
}

@Test func repeatingSameBusinessCommandIsIdempotent() throws {
    var ledger = EntertainmentChipLedger()
    let id = try BusinessID("gift-2026-07-14")
    let day = try LocalDay("2026-07-14")
    let first = try ledger.claimDailyGift(id: id, day: day, at: .distantPast)
    let second = try ledger.claimDailyGift(id: id, day: day, at: .distantFuture)
    #expect(first == second)
    #expect(ledger.balance == try Chips(138_500))
    #expect(ledger.entries.count == 1)
}

@Test func conflictingReuseOfBusinessIDIsRejected() throws {
    var ledger = EntertainmentChipLedger()
    let id = try BusinessID("same-id")
    let table = try TableID("jade")
    _ = try ledger.buyIn(amount: try Chips(4_000), table: table, id: id, at: .distantPast)
    #expect(throws: PokerSessionError.businessIDConflict) {
        try ledger.cashOut(amount: try Chips(4_000), table: table, id: id, at: .distantFuture)
    }
}

@Test func reliefRequiresLowBalanceNoUnsettledBuyInAndOneClaimPerDay() throws {
    var ledger = EntertainmentChipLedger(balance: try Chips(1_500))
    let day = try LocalDay("2026-07-14")
    #expect(throws: PokerSessionError.reliefNotAvailable) {
        try ledger.claimRelief(
            id: try BusinessID("relief-blocked"), day: day,
            at: .distantPast, hasUnsettledBuyIn: true
        )
    }
    let entry = try ledger.claimRelief(
        id: try BusinessID("relief-ok"), day: day,
        at: .distantPast, hasUnsettledBuyIn: false
    )
    #expect(entry.delta == 18_500)
    #expect(ledger.balance == try Chips(20_000))
}
```

还要直接测试余额不足、同日不同业务编号重复领取、跨日领取、加法溢出和解码损坏流水。

- [ ] **步骤 2：运行并确认 RED**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/riverclub-session-task2-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/riverclub-session-task2-clang-cache \
swift test --disable-sandbox --package-path Packages/PokerCore --filter EntertainmentChipLedgerTests
```

预期：编译失败，提示找不到 `EntertainmentChipLedger`。

- [ ] **步骤 3：实现账本值类型**

```swift
public enum LedgerReason: Codable, Equatable, Sendable {
    case cashBuyIn(table: TableID)
    case cashOut(table: TableID)
    case dailyGift(day: LocalDay)
    case bankruptcyRelief(day: LocalDay)
}

public struct LedgerEntry: Codable, Equatable, Sendable {
    public let businessID: BusinessID
    public let timestamp: Date
    public let reason: LedgerReason
    public let balanceBefore: Chips
    public let delta: Int
    public let balanceAfter: Chips
}

public struct EntertainmentChipLedger: Codable, Equatable, Sendable {
    public private(set) var balance: Chips
    public private(set) var entries: [LedgerEntry]
    private var entriesByBusinessID: [BusinessID: LedgerEntry]

    public init(balance: Chips = SessionEconomy.initialBalance) {
        self.balance = balance
        entries = []
        entriesByBusinessID = [:]
    }
}
```

所有命令统一进入私有 `apply(id:reason:delta:at:)`。若业务编号已存在且原因、金额相同，返回旧流水；否则抛 `businessIDConflict`。使用 `addingReportingOverflow` 计算新余额，拒绝负余额和溢出。自定义解码必须重建索引并验证每条流水的前后余额链。

- [ ] **步骤 4：运行账本测试和完整包测试**

预期：账本全部通过；完整包无回归。

- [ ] **步骤 5：提交任务 2**

```bash
git add Packages/PokerCore
git commit -m "feat: 实现幂等娱乐筹码账本"
```

---

### 任务 3：增加 PokerCore 包级可信恢复快照

**文件：**

- 创建：`Packages/PokerCore/Sources/PokerCore/Game/HoldemCheckpoint.swift`
- 修改：`Packages/PokerCore/Sources/PokerCore/Game/HoldemGame.swift`
- 创建：`Packages/PokerCore/Tests/PokerCoreTests/HoldemCheckpointTests.swift`
- 创建：`Packages/PokerCore/Tests/PokerCorePublicAPITests/HoldemCheckpointBoundaryTests.swift`

**接口：**

- 输入：现有内部 `HoldemState` 和公开 `HoldemGame`。
- 产出：仅同一 Swift package target 可见的 `package HoldemCheckpoint`、`HoldemGame.makeCheckpoint()` 和 `HoldemGame.restore(from:)`。

- [ ] **步骤 1：写恢复与边界失败测试**

内部测试：

```swift
@Test func checkpointRoundTripRestoresIdenticalSafeObservationsAndActions() throws {
    let game = try Fixtures.startedNineSeatGame(seed: 77)
    let actor = try #require(game.spectatorObservation().currentActor)
    let before = try game.playerObservation(for: actor)
    let data = try JSONEncoder().encode(game.makeCheckpoint())
    let checkpoint = try JSONDecoder().decode(HoldemCheckpoint.self, from: data)
    let restored = try HoldemGame.restore(from: checkpoint)
    #expect(try restored.playerObservation(for: actor) == before)
    #expect(restored.spectatorObservation() == game.spectatorObservation())
    #expect(restored.lastTransition == game.lastTransition)
}

@Test func corruptCheckpointIsRejectedDuringDecode() throws {
    let data = try Fixtures.checkpointJSONWithDuplicateCard()
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(HoldemCheckpoint.self, from: data)
    }
}
```

非 `@testable` 边界测试只正常 `import PokerCore`，继续证明 `HoldemGame` 不符合 Codable、Mirror 不显示内部状态；另用临时 `swiftc -typecheck` 负向探针确认 `HoldemCheckpoint`、`makeCheckpoint` 和 `restore` 对外不可见，预期 exit code 为 1。

- [ ] **步骤 2：确认 RED**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/riverclub-session-task3-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/riverclub-session-task3-clang-cache \
swift test --disable-sandbox --package-path Packages/PokerCore --filter HoldemCheckpointTests
```

预期：编译失败，提示 `HoldemCheckpoint` 和恢复方法不存在。

- [ ] **步骤 3：实现 package 快照**

```swift
package struct HoldemCheckpoint: Codable, Equatable, Sendable {
    private let state: HoldemState
    private let lastTransition: GameTransition

    init(state: HoldemState, lastTransition: GameTransition) {
        self.state = state
        self.lastTransition = lastTransition
    }

    package func restoredGame() throws -> HoldemGame {
        try StateValidator.validate(state)
        return HoldemGame(restoredState: state, lastTransition: lastTransition)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let state = try values.decode(HoldemState.self, forKey: .state)
        let transition = try values.decode(GameTransition.self, forKey: .lastTransition)
        do {
            try StateValidator.validate(state)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Invalid Holdem checkpoint",
                      underlyingError: error)
            )
        }
        self.state = state
        lastTransition = transition
    }

    private enum CodingKeys: String, CodingKey { case state, lastTransition }
}
```

在 `HoldemGame.swift` 内增加 internal 的状态桥接和 package 方法；不要把 `state` 改为 public/package，也不要让 `HoldemGame` 遵循 Codable。

- [ ] **步骤 4：运行恢复、公开边界和完整包测试**

预期：恢复后安全观察、合法动作和转换一致；损坏状态拒绝；外部负向探针失败；完整测试通过。

- [ ] **步骤 5：提交任务 3**

```bash
git add Packages/PokerCore
git commit -m "feat: 增加包级可信牌局恢复"
```

---

### 任务 4：实现普通桌会话生命周期

**文件：**

- 创建：`Packages/PokerCore/Sources/PokerSession/Cash/CashGameSession.swift`
- 创建：`Packages/PokerCore/Tests/PokerSessionTests/CashGameSessionTests.swift`

**接口：**

- 输入：任务 3 的 package checkpoint、`HandConfig`、九座位筹码和动作。
- 产出：package `CashGameSession` 状态机；public `CashSessionView`、`CashSessionPhase`；安全观察与脱敏事件。

- [ ] **步骤 1：写边界和生命周期失败测试**

```swift
@Test func buyInBoundsAreFortyThroughOneHundredBigBlinds() throws {
    let config = try HandConfig(smallBlind: try Chips(50), bigBlind: try Chips(100), dealer: try SeatID(0))
    #expect(throws: PokerSessionError.invalidBuyIn) {
        try CashGameSession.make(
            id: try SessionID("s-low"), table: try TableID("jade"), config: config,
            humanSeat: try SeatID(0), stacks: Fixtures.nineStacks(human: 3_999)
        )
    }
    _ = try CashGameSession.make(
        id: try SessionID("s-min"), table: try TableID("jade"), config: config,
        humanSeat: try SeatID(0), stacks: Fixtures.nineStacks(human: 4_000)
    )
    _ = try CashGameSession.make(
        id: try SessionID("s-max"), table: try TableID("jade"), config: config,
        humanSeat: try SeatID(0), stacks: Fixtures.nineStacks(human: 10_000)
    )
}

@Test func sessionCannotStartNextHandUntilPendingSettlementIsCommitted() throws {
    var session = try Fixtures.cashSession()
    try session.startHand(id: try HandID("h1"), seed: 4, startedAt: .distantPast)
    try Fixtures.finishByImmediateFold(session: &session)
    #expect(session.view.phase == .settlementPending)
    #expect(throws: PokerSessionError.settlementPending) {
        try session.startHand(id: try HandID("h2"), seed: 5, startedAt: .distantFuture)
    }
}

@Test func committingHandAdvancesDealerAndPreservesFinalStacks() throws {
    var session = try Fixtures.completedCashSession()
    let pending = try #require(session.pendingHand)
    try session.markHandCommitted(pending.id)
    #expect(session.view.completedHands == 1)
    #expect(session.view.dealer == try SeatID(1))
    #expect(session.view.phase == .readyForNextHand)
}
```

另测：必须恰好九个唯一座位、真人座位存在、所有筹码正数；进行中不能离桌；非法动作不改变 checkpoint；恢复后观察一致。

- [ ] **步骤 2：运行并确认 RED**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/riverclub-session-task4-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/riverclub-session-task4-clang-cache \
swift test --disable-sandbox --package-path Packages/PokerCore --filter CashGameSessionTests
```

预期：编译失败，提示找不到 `CashGameSession`。

- [ ] **步骤 3：实现内部状态机和公开只读视图**

```swift
public enum CashSessionPhase: String, Codable, Equatable, Sendable {
    case readyForHand, handInProgress, settlementPending, left
}

public struct CashSessionView: Codable, Equatable, Sendable {
    public let id: SessionID
    public let table: TableID
    public let humanSeat: SeatID
    public let phase: CashSessionPhase
    public let dealer: SeatID
    public let completedHands: Int
    public let seats: [CashSeatView]
    public let currentActor: SeatID?
}

public struct CashSeatView: Codable, Equatable, Sendable {
    public let id: SeatID
    public let stack: Chips
    public let hasFolded: Bool
    public let isAllIn: Bool
}

package struct PendingCashHand: Codable, Equatable, Sendable {
    package let id: HandID
    package let startedAt: Date
    package let record: CompletedHandRecord
}

package struct CashGameSession: Codable, Equatable, Sendable {
    package let id: SessionID
    package let table: TableID
    package let humanSeat: SeatID
    package var config: HandConfig
    package var phase: CashSessionPhase
    package var completedHands: Int
    package var stacks: [SeatID: Chips]
    package var checkpoint: HoldemCheckpoint?
    package var pendingHand: PendingCashHand?
}
```

每次动作从 checkpoint 恢复临时 `HoldemGame`，成功后写回新 checkpoint；失败不替换旧 checkpoint。若观察进入 `.complete`，立即生成 `PendingCashHand` 并把 phase 改为 `.settlementPending`。提交后使用 `record.finalStacks` 更新 stacks，庄位按 SeatID 循环到下一座位。

- [ ] **步骤 4：运行会话和完整包测试**

预期：生命周期、连续两手和非法动作原子性测试通过。

- [ ] **步骤 5：提交任务 4**

```bash
git add Packages/PokerCore
git commit -m "feat: 实现普通桌会话状态机"
```

---

### 任务 5：实现版本化聚合状态与原子文件仓库

**文件：**

- 创建：`Packages/PokerCore/Sources/PokerSession/Persistence/PersistedAppState.swift`
- 创建：`Packages/PokerCore/Sources/PokerSession/Persistence/FileSessionRepository.swift`
- 创建：`Packages/PokerCore/Tests/PokerSessionTests/FileSessionRepositoryTests.swift`

**接口：**

- 输入：账本、普通桌会话、牌局记录和统计。
- 产出：package `PersistedAppState`、`SessionRepository`、`FileSessionRepository`、可注入 `AtomicFileWriting`。

- [ ] **步骤 1：写原子性、版本和损坏文件失败测试**

```swift
@Test func saveThenLoadRoundTripsWholeAggregate() throws {
    let directory = try TemporaryDirectory()
    let repository = FileSessionRepository(directory: directory.url)
    let state = try Fixtures.persistedStateWithLedgerAndSession()
    try repository.save(state)
    #expect(try repository.load() == state)
}

@Test func failureBeforeReplacePreservesPreviousCommittedFile() throws {
    let directory = try TemporaryDirectory()
    let writer = FailingAtomicWriter(failAt: .beforeReplace)
    let repository = FileSessionRepository(directory: directory.url, writer: writer)
    let old = try Fixtures.persistedState(balance: 128_500)
    try writer.allow { try repository.save(old) }
    #expect(throws: PokerSessionError.persistenceFailed) {
        try repository.save(Fixtures.persistedState(balance: 100))
    }
    #expect(try writer.allow { try repository.load() } == old)
}

@Test func unsupportedVersionAndCorruptJSONDoNotResetAccount() throws {
    let repository = try Fixtures.repositoryContaining(version: 99)
    #expect(throws: PokerSessionError.unsupportedVersion(99)) { try repository.load() }
    try repository.replaceFileWithInvalidJSON()
    #expect(throws: PokerSessionError.corruptSnapshot) { try repository.load() }
}
```

分别注入 `.afterTemporaryWrite`、`.afterSynchronize`、`.beforeReplace` 失败点，验证正式文件仍为旧版本且临时文件会清理。

- [ ] **步骤 2：确认 RED**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/riverclub-session-task5-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/riverclub-session-task5-clang-cache \
swift test --disable-sandbox --package-path Packages/PokerCore --filter FileSessionRepositoryTests
```

预期：编译失败，提示仓库类型不存在。

- [ ] **步骤 3：实现聚合根与文件替换**

```swift
package struct PlayerStatistics: Codable, Equatable, Sendable {
    package var completedHands = 0
    package var wonHands = 0
    package var totalCommitted = 0
    package var netChange = 0
    package var largestWin = 0
}

package struct PersistedAppState: Codable, Equatable, Sendable {
    package static let currentVersion = 1
    package var version = currentVersion
    package var ledger = EntertainmentChipLedger()
    package var activeCashSession: CashGameSession?
    package var records: [HandID: StoredHandRecord] = [:]
    package var recordOrder: [HandID] = []
    package var statistics = PlayerStatistics()
}

package protocol SessionRepository {
    func load() throws -> PersistedAppState
    func save(_ state: PersistedAppState) throws
}
```

`FileSessionRepository` 固定使用调用方目录下 `river-club-state-v1.json`。编码使用排序 key；写同目录唯一临时文件，`FileHandle.write` 后调用 `synchronize()` 和 `close()`，再以 `replaceItemAt` 或首次 `moveItem` 切换正式文件。所有底层错误映射为 `persistenceFailed`，解码错误映射为 `corruptSnapshot`，不自动创建新账户覆盖坏文件。

只有正式文件不存在时，`load()` 才返回新的 `PersistedAppState()`；文件存在但为空、损坏或版本不支持时必须抛错，不能回退到新账户。

- [ ] **步骤 4：运行仓库和完整包测试**

预期：所有失败注入保持旧正式状态；完整包测试通过。

- [ ] **步骤 5：提交任务 5**

```bash
git add Packages/PokerCore
git commit -m "feat: 实现版本化原子文件存档"
```

---

### 任务 6：实现原子业务门面、结算记录和统计

**文件：**

- 创建：`Packages/PokerCore/Sources/PokerSession/History/HandHistory.swift`
- 创建：`Packages/PokerCore/Sources/PokerSession/Store/LocalPokerStore.swift`
- 创建：`Packages/PokerCore/Tests/PokerSessionTests/LocalPokerStoreTests.swift`

**接口：**

- 输入：任务 2 账本、任务 4 会话、任务 5 Repository。
- 产出：应用唯一公开业务入口 `LocalPokerStore`；`CashTableRequest`、`StoredHandRecord`、`PlayerStatisticsView`。

- [ ] **步骤 1：写买入、行动、结算、失败回滚和离桌测试**

```swift
@Test func sittingDownAtomicallyDebitsLedgerAndCreatesSession() throws {
    let repository = InMemorySessionRepository()
    let store = try LocalPokerStore(repository: repository, clock: Fixtures.clock)
    let view = try store.sitDown(
        request: Fixtures.nineSeatRequest(humanBuyIn: 4_000),
        businessID: try BusinessID("buy-jade-1")
    )
    #expect(view.phase == .readyForHand)
    #expect(store.accountBalance == try Chips(124_500))
    #expect(repository.saveCount == 1)
}

@Test func repositoryFailureDoesNotExposePartiallyAppliedAction() throws {
    let repository = try FailingSessionRepository(afterSuccessfulSaves: 1)
    let store = try Fixtures.storeWithActiveHand(repository: repository)
    let actor = try #require(store.spectatorObservation?.currentActor)
    let before = store.spectatorObservation
    #expect(throws: PokerSessionError.persistenceFailed) {
        try store.apply(.fold, by: actor)
    }
    #expect(store.spectatorObservation == before)
}

@Test func settlementRetryWithSameHandIDIsIdempotent() throws {
    let store = try Fixtures.storeWithCompletedPendingHand(id: "h-1")
    let first = try store.commitPendingHand(transactionID: try BusinessID("settle-h-1"))
    let second = try store.commitPendingHand(transactionID: try BusinessID("settle-h-1"))
    #expect(first == second)
    #expect(store.handRecords().count == 1)
    #expect(store.statistics.completedHands == 1)
}

@Test func leavingReturnsExactHumanStackAndClearsActiveSession() throws {
    let store = try Fixtures.storeReadyToLeave(humanStack: 6_250)
    try store.leave(businessID: try BusinessID("leave-jade-1"))
    #expect(store.accountBalance == try Chips(130_750))
    #expect(store.cashSession == nil)
}
```

另测：进行中或待提交时离桌失败；相同业务编号重复买入、离桌、赠送和救济幂等；保存失败后内存状态与最后提交文件一致。

- [ ] **步骤 2：确认 RED**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/riverclub-session-task6-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/riverclub-session-task6-clang-cache \
swift test --disable-sandbox --package-path Packages/PokerCore --filter LocalPokerStoreTests
```

预期：编译失败，提示 `LocalPokerStore` 不存在。

- [ ] **步骤 3：实现历史类型和事务复制提交**

```swift
public struct StoredHandRecord: Codable, Equatable, Sendable {
    public let id: HandID
    public let sessionID: SessionID
    public let table: TableID
    public let startedAt: Date
    public let endedAt: Date
    public let localDay: LocalDay
    public let handNumber: Int
    public let record: CompletedHandRecord
}

public struct PlayerStatisticsView: Codable, Equatable, Sendable {
    public let completedHands: Int
    public let wonHands: Int
    public let totalCommitted: Int
    public let netChange: Int
    public let largestWin: Int
}

public struct CashTableRequest: Equatable, Sendable {
    public let sessionID: SessionID
    public let table: TableID
    public let config: HandConfig
    public let humanSeat: SeatID
    public let stacks: [SeatID: Chips]

    public init(
        sessionID: SessionID,
        table: TableID,
        config: HandConfig,
        humanSeat: SeatID,
        stacks: [SeatID: Chips]
    ) {
        self.sessionID = sessionID
        self.table = table
        self.config = config
        self.humanSeat = humanSeat
        self.stacks = stacks
    }
}

public final class LocalPokerStore {
    private let repository: any SessionRepository
    private let clock: any SessionClock
    private var committed: PersistedAppState

    package init(repository: any SessionRepository, clock: any SessionClock) throws {
        self.repository = repository
        self.clock = clock
        committed = try repository.load()
    }

    private func transact<Result>(
        _ operation: (inout PersistedAppState) throws -> Result
    ) throws -> Result {
        var candidate = committed
        let result = try operation(&candidate)
        do { try repository.save(candidate) }
        catch { throw PokerSessionError.persistenceFailed }
        committed = candidate
        return result
    }
}
```

公开读取接口固定为：

```swift
public var accountBalance: Chips { get }
public var cashSession: CashSessionView? { get }
public var spectatorObservation: SpectatorObservation? { get }
public func playerObservation(for seat: SeatID) throws -> PlayerObservation?
public var statistics: PlayerStatisticsView { get }
public func handRecords(filter: HandRecordFilter = .init()) -> [StoredHandRecord]
```

公开命令接口固定为：

```swift
public func sitDown(request: CashTableRequest, businessID: BusinessID) throws -> CashSessionView
public func startHand(id: HandID, seed: UInt64) throws -> GameTransition
public func apply(_ action: PlayerAction, by seat: SeatID) throws -> GameTransition
public func advanceIfRoundComplete() throws -> GameTransition
public func commitPendingHand(transactionID: BusinessID) throws -> StoredHandRecord
public func leave(businessID: BusinessID) throws
public func claimDailyGift(businessID: BusinessID) throws -> LedgerEntry
public func claimRelief(businessID: BusinessID) throws -> LedgerEntry
```

公开工厂 `LocalPokerStore.open(directory:clock:)` 创建文件仓库。`sitDown` 在同一 candidate 中执行账本买入与会话创建。`startHand`、`apply`、`advanceIfRoundComplete` 每次成功后保存 checkpoint。`commitPendingHand` 用稳定 handID 去重，同时写记录、更新统计并调用会话 `markHandCommitted`。`leave` 在同一 candidate 中退回真人 stack 并清除活跃会话。

统计计算使用 `CompletedHandRecord`：投入为真人 `settledCommitments`，净变化为 `chipDeltas`，真人获得奖励时计为获胜，正净变化更新最大单手赢取；所有加法使用受检算术。

- [ ] **步骤 4：运行门面、会话、账本和完整包测试**

预期：事务失败不改变公开状态；结算重试不重复记录或统计；完整包通过。

- [ ] **步骤 5：提交任务 6**

```bash
git add Packages/PokerCore
git commit -m "feat: 实现普通桌原子业务事务"
```

---

### 任务 7：实现历史查询删除、恢复集成和随机命令属性测试

**文件：**

- 修改：`Packages/PokerCore/Sources/PokerSession/History/HandHistory.swift`
- 修改：`Packages/PokerCore/Sources/PokerSession/Store/LocalPokerStore.swift`
- 创建：`Packages/PokerCore/Tests/PokerSessionTests/SessionRecoveryTests.swift`
- 创建：`Packages/PokerCore/Tests/PokerSessionTests/SessionPropertyTests.swift`
- 创建：`Packages/PokerCore/Tests/PokerSessionPublicAPITests/PokerSessionBoundaryTests.swift`

**接口：**

- 输入：完整业务门面和文件仓库。
- 产出：历史筛选、单局删除、确认后全部清空、恢复与 100 序列属性审计。

- [ ] **步骤 1：写历史和恢复失败测试**

```swift
@Test func unfinishedHandNeverAppearsInHistory() throws {
    let store = try Fixtures.storeWithActiveHand()
    #expect(store.handRecords().isEmpty)
}

@Test func completedHistoryContainsFoldedCardsAndSurvivesReopen() throws {
    let directory = try TemporaryDirectory()
    let first = try Fixtures.completeAndCommitHand(in: directory.url)
    let foldedSeat = try #require(first.record.actions.first(where: {
        if case .fold = $0.action { return true }; return false
    })?.seat)
    #expect(first.record.holeCardsBySeat[foldedSeat]?.count == 2)
    let reopened = try LocalPokerStore.open(directory: directory.url, clock: Fixtures.clock)
    #expect(reopened.handRecords() == [first])
}

@Test func deletingHistoryDoesNotChangeLedger() throws {
    let store = try Fixtures.storeWithTwoRecords()
    let balance = store.accountBalance
    try store.deleteHand(id: store.handRecords()[0].id)
    #expect(store.accountBalance == balance)
    try store.deleteAllHands(confirmation: .confirmed)
    #expect(store.accountBalance == balance)
    #expect(store.handRecords().isEmpty)
}
```

- [ ] **步骤 2：写 100 序列确定性属性测试并确认 RED**

使用固定线性同余生成器生成至少 100 组命令序列。每组从新账户开始，在合法条件下选择赠送、救济、买入、开局、合法动作、结算和离桌。每步断言：

```swift
#expect(store.accountBalance.rawValue >= 0)
#expect(
    store.accountBalance.rawValue
    + (store.cashSession?.seats.reduce(0) { $0 + $1.stack.rawValue } ?? 0)
    == expectedTotal
)
#expect(Set(store.handRecords().map(\.id)).count == store.handRecords().count)
#expect(store.statistics.completedHands == store.handRecords().count)
```

对同一初始文件和相同命令序列运行两遍，最终 JSON、余额、记录和统计必须相同；重复全部幂等业务编号后结果不得变化。

- [ ] **步骤 3：实现查询与删除 API**

```swift
public struct HandRecordFilter: Equatable, Sendable {
    public let table: TableID?
    public let localDay: LocalDay?
    public init(table: TableID? = nil, localDay: LocalDay? = nil) {
        self.table = table
        self.localDay = localDay
    }
}

public enum DeleteAllConfirmation: Sendable { case confirmed }
```

`handRecords(filter:)` 按 `recordOrder` 倒序返回，只读取已提交 records。`deleteHand` 和 `deleteAllHands` 通过 `transact` 原子更新 records/order，不改变 ledger、active session 或 statistics。日期筛选由注入的日历转换器在记录提交时固化 `LocalDay`，查询时不重新解释时区。

Public API 测试正常 `import PokerSession`，验证 `CashGameSession`、`PersistedAppState`、`HoldemCheckpoint`、`SessionRepository` 和完整 checkpoint 方法不可见；可见对象只能得到安全观察、脱敏转换和已完成记录。

- [ ] **步骤 4：运行两遍完整测试**

运行完整 `swift test` 两次。预期两遍测试数量一致、全部通过；100 组属性摘要一致；PokerCore 原 500 种子测试继续通过。

- [ ] **步骤 5：提交任务 7**

```bash
git add Packages/PokerCore
git commit -m "test: 验证普通桌恢复与事务不变量"
```

---

### 任务 8：接入 XcodeGen 并执行通用 iOS 构建

**文件：**

- 修改：`project.yml`
- 验证：`RiverClub.xcodeproj`

**接口：**

- 输入：`PokerCore` package 中的新 `PokerSession` product。
- 产出：RiverClub 应用和单元测试目标可 `import PokerSession`。

- [ ] **步骤 1：先增加应用侧编译测试**

在 `RiverClubTests/PokerSessionImportTests.swift` 中写：

```swift
import XCTest
import PokerSession
import PokerCore

final class PokerSessionImportTests: XCTestCase {
    func testApprovedEconomyConstantsAreAvailableToApplication() throws {
        XCTAssertEqual(SessionEconomy.initialBalance, try Chips(128_500))
    }
}
```

未修改 XcodeGen 依赖前运行生成与构建，预期 `no such module 'PokerSession'`。

- [ ] **步骤 2：修改 project.yml 依赖，不覆盖现有配置**

为 `RiverClub` 和 `RiverClubTests` 的 dependencies 各增加：

```yaml
- package: PokerCore
  product: PokerSession
```

保留现有 bundle identifier、iPhone-only、iOS 18、左右横屏、PokerCore 和 UI 测试设置。

- [ ] **步骤 3：运行生成、包测试和通用 iOS 构建**

```bash
xcodegen generate
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/riverclub-session-final-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/riverclub-session-final-clang-cache \
swift test --disable-sandbox --package-path Packages/PokerCore
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub \
-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

预期：XcodeGen exit 0；完整包测试通过；通用 iOS 构建输出 `TEST BUILD SUCCEEDED`。若沙箱拒绝 Xcode 缓存，使用相同命令申请沙箱外运行并记录首次失败与最终真实 exit code。

- [ ] **步骤 4：检查差异和工作区**

```bash
git diff --check
git status --short
```

预期：无空白错误；只包含本任务应提交文件。

- [ ] **步骤 5：提交任务 8**

```bash
git add project.yml RiverClubTests RiverClub.xcodeproj
git commit -m "build: 接入普通桌会话模块"
```

---

## 完成标准

- 普通桌 40–100 个大盲买入、九人连续多手、结算、离桌和重新买入均通过直接测试。
- 初始余额、每日赠送和破产救济额度与资格被测试锁定，所有业务命令幂等。
- 每个动作、买入、结算、删除和离桌只有在原子文件保存成功后才改变公开已提交状态。
- 应用中断后可恢复相同安全观察和合法动作；损坏或不支持版本不会静默重置账户。
- 只有完成手牌进入历史，且记录包含所有已获发底牌玩家，包括弃牌者。
- public API 不暴露 checkpoint、牌堆、随机种子、对手底牌或完整规则状态。
- 100 组随机会话命令满足余额/桌上筹码守恒、记录唯一、统计幂等和确定性。
- PokerCore 500 种子属性测试保持通过。
- XcodeGen 和通用 iOS `build-for-testing` 成功。

## 后续计划边界

本计划完成后再独立设计并实施：

1. 单桌锦标赛、淘汰、名次、奖励和两种涨盲方式。
2. 三档难度、四种模型和全局机器人参数。
3. GameCoordinator、倒计时、SwiftUI 牌桌接入和牌局记录查看器。
