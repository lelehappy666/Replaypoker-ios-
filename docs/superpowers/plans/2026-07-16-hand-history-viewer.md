# River Club 真实牌局存档查看器实施计划

> **供代理执行：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务执行本计划。所有步骤使用复选框跟踪。

**目标：** 把侧边栏“我的牌局”接入唯一 `LocalPokerStore` 的真实完成记录，提供最终结果详情、日期/牌桌筛选和安全删除，同时保持正常游戏与机器人的隐藏信息边界。

**架构：** `PokerSession` 负责安全显示元数据、日期范围查询和原子删除；`PokerCoordinator` 在结算时把冻结牌桌名、真人座位与九个玩家名和完成记录一起提交；`AppSession` 是唯一存储入口并维护可观察页面状态；`RiverClub/Features/History` 只消费完成记录转换出的只读展示模型。大厅牌桌浏览拆到非侧边栏路由，避免继续与“我的牌局”复用 `.tables`。

**技术栈：** Swift 6、SwiftUI、Observation、PokerCore、PokerSession、PokerCoordinator、XCTest、Swift Testing、XCUITest、XcodeGen。

## 全局约束

- 所有说明文档、规格、计划、交付说明和 Git/GitHub 提交信息必须使用中文。
- 目标设备为 iPhone 16 Pro Max，全程只支持横屏；自动化可使用本机可用的最新 Pro Max 模拟器，但必须保留 iPhone 16 Pro Max 真机视觉验收。
- 只有已经完成并原子保存的 `StoredHandRecord` 可以显示所有最终底牌，包括弃牌玩家。
- 正常牌桌、机器人、旁观观察和普通 `import PokerCoordinator` 不能访问对手底牌、牌堆、随机种子、完整检查点、任意玩家观察或待结算隐藏对象。
- `AppSession` 持有且只持有一个 `LocalPokerStore`；存档页面不得创建第二个 store 或直接读取 JSON 文件。
- 存档首版只显示最终结果，不实现逐动作牌谱、回放、导出、分享、云同步、搜索、标签、收藏、分页或锦标赛存档。
- 单局删除和全部删除必须二次确认；删除不能修改余额、账本、统计、当前会话、命令回执或永久身份集合。
- 新记录冻结牌桌名、真人座位和九个座位显示名；旧记录缺少元数据时必须降级显示，不能改写旧记录或重置存档。
- 完整离桌结算和离桌后重新入座仍不在本计划范围内。

---

## 文件结构

### PokerSession

- 修改 `Packages/PokerCore/Sources/PokerSession/History/HandHistory.swift`：安全存档元数据、日期范围和查询过滤器。
- 修改 `Packages/PokerCore/Sources/PokerSession/Store/LocalPokerStore.swift`：带元数据的幂等结算、稳定筛选和既有删除事务。
- 修改 `Packages/PokerCore/Tests/PokerSessionTests/SessionRecoveryTests.swift`：旧记录兼容、日期/牌桌组合查询与删除不变量。
- 修改 `Packages/PokerCore/Tests/PokerSessionTests/LocalPokerStoreTests.swift`：元数据验证、幂等冲突和写入失败。
- 修改 `Packages/PokerCore/Tests/PokerSessionTests/SessionPropertyTests.swift`：所有结算调用提供稳定元数据。
- 新建 `Packages/PokerCore/Tests/PokerSessionTests/Support/HandHistoryTestSupport.swift`：统一生成查询记录和测试元数据。

### PokerCoordinator

- 修改 `Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableCoordinator.swift`：冻结并提交存档显示元数据。
- 修改 `Packages/PokerCore/Tests/PokerCoordinatorTests/SettlementPipelineTests.swift`：结算、失败重试和元数据冻结。
- 修改 `Packages/PokerCore/Tests/PokerCoordinatorTests/Support/CoordinatorTestSupport.swift`：协调器夹具注入元数据。

### RiverClub 应用状态与导航

- 修改 `RiverClub/App/AppSession.swift`：历史依赖、可观察状态、筛选、选择和删除动作。
- 修改 `RiverClub/App/AppRootView.swift`：独立牌桌浏览路由与真实存档入口。
- 修改 `RiverClub/DesignSystem/AppSidebar.swift`：保持“我的牌局”侧边栏语义，处理新牌桌浏览路由。

### RiverClub 存档功能

- 新建 `RiverClub/Features/History/HandHistoryPresentation.swift`：完成记录到列表、座位、底池展示模型的纯转换。
- 新建 `RiverClub/Features/History/HandHistoryViewState.swift`：日期选择、牌桌选择、加载/失败/删除状态。
- 新建 `RiverClub/Features/History/HandHistoryView.swift`：横屏列表、筛选、空态、菜单和确认弹窗。
- 新建 `RiverClub/Features/History/HandHistoryDetailView.swift`：公共牌、九座位最终底牌、底池与赢家详情。
- 修改 `project.yml`：显式纳入新增源文件（若 target 使用目录通配则只验证生成结果，不制造无意义 diff）。

### 测试与文档

- 新建 `RiverClubTests/HandHistoryPresentationTests.swift`。
- 新建 `RiverClubTests/Support/HandHistoryPresentationTestSupport.swift`。
- 新建 `RiverClubTests/HandHistorySessionTests.swift`。
- 新建 `RiverClubTests/HandHistoryLayoutTests.swift`。
- 新建 `RiverClubTests/Support/HandHistoryAppTestSupport.swift`。
- 修改 `RiverClubTests/AppSessionTests.swift`。
- 新建 `RiverClubUITests/HandHistoryFlowUITests.swift`。
- 修改 `README.md`：把“UI 原型/无规则引擎”的过时描述更新为当前本地可玩闭环与真实存档说明。

---

### 任务 1：扩展安全完成记录、日期范围与向后兼容

**文件：**

- 修改：`Packages/PokerCore/Sources/PokerSession/History/HandHistory.swift`
- 修改：`Packages/PokerCore/Sources/PokerSession/Store/LocalPokerStore.swift`
- 修改：`Packages/PokerCore/Tests/PokerSessionTests/SessionRecoveryTests.swift`
- 新建：`Packages/PokerCore/Tests/PokerSessionTests/Support/HandHistoryTestSupport.swift`

**接口：**

- 消费：`StoredHandRecord`、`LocalDay`、现有 `LocalPokerStore.commitPendingHand(transactionID:)`、`LocalPokerStore.handRecords(filter:)`。
- 产出：

```swift
public struct HandArchiveMetadata: Codable, Equatable, Sendable {
    public let tableDisplayName: String
    public let humanSeat: SeatID
    public let seatDisplayNames: [SeatID: String]

    public init(
        tableDisplayName: String,
        humanSeat: SeatID,
        seatDisplayNames: [SeatID: String]
    ) throws
}

public struct HandRecordDateRange: Equatable, Sendable {
    public let first: LocalDay
    public let last: LocalDay
    public init(first: LocalDay, last: LocalDay) throws
    public func contains(_ day: LocalDay) -> Bool
}

public struct HandRecordFilter: Equatable, Sendable {
    public let table: TableID?
    public let localDay: LocalDay?
    public let dateRange: HandRecordDateRange?

    public init(table: TableID? = nil, localDay: LocalDay? = nil)
    public init(table: TableID? = nil, dateRange: HandRecordDateRange)
}

```

- `StoredHandRecord` 新增 `public let archiveMetadata: HandArchiveMetadata?`；旧 JSON 缺少字段时解码为 `nil`。
- 测试支持产出：

```swift
func makeArchiveMetadata(
    tableName: String = "测试牌桌",
    humanSeat: SeatID = SeatID(rawValue: 0)!
) throws -> HandArchiveMetadata

struct HistoryQueryFixture {
    let store: LocalPokerStore
    init() throws
    func save(
        table: String,
        day: String,
        endedAt: TimeInterval,
        hand: Int
    ) throws
}
```

`HistoryQueryFixture.save` 必须使用真实 `sitDown → startHand → 合法动作完成 → commitPendingHand` 命令，并通过可变测试时钟设置结束时间和 `LocalDay`；不能直接修改 `PersistedAppState` 或伪造 records 字典。

- [ ] **步骤 1：先写元数据、兼容和筛选失败测试**

在 `SessionRecoveryTests.swift` 增加：

```swift
@Test func 旧记录缺少显示元数据仍能解码且不会被改写() throws {
    let legacy = try storedRecord(id: "legacy-history", archiveMetadata: nil)
    let data = try JSONEncoder().encode(legacy)
    let decoded = try JSONDecoder().decode(StoredHandRecord.self, from: data)

    #expect(decoded.archiveMetadata == nil)
    #expect(decoded == legacy)
}

@Test func 日期范围与牌桌筛选组合并保持稳定倒序() throws {
    let fixture = try HistoryQueryFixture()
    try fixture.save(table: "table-a", day: "2027-01-10", endedAt: 100, hand: 1)
    try fixture.save(table: "table-a", day: "2027-01-12", endedAt: 300, hand: 2)
    try fixture.save(table: "table-b", day: "2027-01-11", endedAt: 200, hand: 3)
    let range = try HandRecordDateRange(
        first: LocalDay("2027-01-10"),
        last: LocalDay("2027-01-12")
    )

    let records = fixture.store.handRecords(
        filter: HandRecordFilter(table: try TableID("table-a"), dateRange: range)
    )

    #expect(records.map(\.handNumber) == [2, 1])
}
```

- [ ] **步骤 2：运行测试确认 RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --package-path Packages/PokerCore \
  --filter '旧记录缺少显示元数据|日期范围与牌桌筛选'
```

预期：编译失败，提示 `HandArchiveMetadata`、`HandRecordDateRange` 和 `archiveMetadata` 不存在。

- [ ] **步骤 3：实现安全元数据和日期范围**

在 `HandHistory.swift` 实现以下验证：

```swift
public struct HandArchiveMetadata: Codable, Equatable, Sendable {
    public let tableDisplayName: String
    public let humanSeat: SeatID
    public let seatDisplayNames: [SeatID: String]

    public init(
        tableDisplayName: String,
        humanSeat: SeatID,
        seatDisplayNames: [SeatID: String]
    ) throws {
        let tableName = tableDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tableName.isEmpty,
              seatDisplayNames.count == 9,
              seatDisplayNames[humanSeat] != nil
        else { throw PokerSessionError.invalidTable }

        var names: [SeatID: String] = [:]
        for (seat, displayName) in seatDisplayNames {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw PokerSessionError.invalidTable }
            names[seat] = name
        }
        self.tableDisplayName = tableName
        self.humanSeat = humanSeat
        self.seatDisplayNames = names
    }
}

public struct HandRecordDateRange: Equatable, Sendable {
    public let first: LocalDay
    public let last: LocalDay

    public init(first: LocalDay, last: LocalDay) throws {
        guard first.rawValue <= last.rawValue else {
            throw PokerSessionError.invalidIdentifier
        }
        self.first = first
        self.last = last
    }

    public func contains(_ day: LocalDay) -> Bool {
        first.rawValue <= day.rawValue && day.rawValue <= last.rawValue
    }
}
```

为 `StoredHandRecord` 增加可选字段和带默认值的构造参数：

```swift
public let archiveMetadata: HandArchiveMetadata?

public init(
    id: HandID,
    transactionID: BusinessID? = nil,
    sessionID: SessionID,
    table: TableID,
    startedAt: Date,
    endedAt: Date,
    localDay: LocalDay,
    handNumber: Int,
    record: CompletedHandRecord,
    archiveMetadata: HandArchiveMetadata? = nil
)
```

使用显式 `CodingKeys` 和 `decodeIfPresent` 保证旧记录缺少 `archiveMetadata` 时正常解码；编码新记录时只编码已有值。

- [ ] **步骤 4：实现稳定查询，并暂时保持旧结算入口**

任务 1 只扩展存档值类型和读取能力。现有 `commitPendingHand(transactionID:)` 在本任务中保持签名不变，并用 `archiveMetadata: nil` 构造新增字段，避免协调器尚未接线时破坏中间提交的编译状态；任务 2 将一次性改为必传元数据并移除旧入口。

查询使用：

```swift
return committed.records.values
    .filter { record in
        (filter.table == nil || record.table == filter.table)
            && (filter.localDay == nil || record.localDay == filter.localDay)
            && (filter.dateRange == nil || filter.dateRange!.contains(record.localDay))
    }
    .sorted {
        if $0.endedAt != $1.endedAt { return $0.endedAt > $1.endedAt }
        if $0.handNumber != $1.handNumber { return $0.handNumber > $1.handNumber }
        return $0.id.rawValue > $1.id.rawValue
    }
```

- [ ] **步骤 5：运行测试与 PokerSession 回归**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --package-path Packages/PokerCore --filter PokerSessionTests
```

预期：PokerSession 全部测试通过，0 失败。

- [ ] **步骤 6：中文提交**

```bash
git add Packages/PokerCore/Sources/PokerSession Packages/PokerCore/Tests/PokerSessionTests
git commit -m "feat: 扩展安全牌局存档元数据与筛选"
```

---

### 任务 2：让协调器冻结并原子提交存档元数据

**文件：**

- 修改：`Packages/PokerCore/Sources/PokerSession/Store/LocalPokerStore.swift`
- 修改：`Packages/PokerCore/Tests/PokerSessionTests/LocalPokerStoreTests.swift`
- 修改：`Packages/PokerCore/Tests/PokerSessionTests/SessionPropertyTests.swift`
- 修改：`Packages/PokerCore/Tests/PokerSessionTests/Support/HandHistoryTestSupport.swift`
- 修改：`Packages/PokerCore/Sources/PokerCoordinator/Cash/CashTableCoordinator.swift`
- 修改：`Packages/PokerCore/Tests/PokerCoordinatorTests/SettlementPipelineTests.swift`
- 修改：`Packages/PokerCore/Tests/PokerCoordinatorTests/Support/CoordinatorTestSupport.swift`
- 修改：`RiverClub/App/AppSession.swift`
- 修改：`RiverClubTests/CashTableEntryTests.swift`
- 修改：`RiverClubTests/Support/AppSessionTestSupport.swift`（若夹具位于其他同目录文件，则修改实际文件）

**接口：**

- 消费：任务 1 的 `HandArchiveMetadata` 和暂时保留的旧结算入口。
- 产出：唯一的 `commitPendingHand(transactionID:archiveMetadata:)`；`CashTableCoordinator` 的两个初始化入口新增 `archiveMetadata: HandArchiveMetadata`；`AppSession` 从所选牌桌和冻结 profiles 构造元数据。

测试支持产出：

```swift
func makeArchiveMetadata(
    tableName: String = "测试牌桌",
    humanSeat: SeatID = SeatID(rawValue: 0)!
) throws -> HandArchiveMetadata

func makeCoordinatorArchiveMetadata(
    tableName: String = "测试牌桌"
) throws -> HandArchiveMetadata

extension CoordinatorScenario {
    static func pendingSettlement(
        repository: FailOnceSessionRepository,
        archiveMetadata: HandArchiveMetadata
    ) async throws -> CoordinatorScenario
}

@MainActor
final class ArchiveMetadataCapture {
    private(set) var value: HandArchiveMetadata?
    func record(_ metadata: HandArchiveMetadata)
}
```

`AppSessionFixture` 的协调器工厂使用 `ArchiveMetadataCapture` 记录收到的不可变元数据，再创建真实协调器；测试只能观察依赖参数，不能绕过 `joinCashTable` 或直接伪造存档。

- [ ] **步骤 1：写协调器冻结与重试失败测试**

在 `LocalPokerStoreTests.swift` 先增加元数据幂等测试：

```swift
@Test func 新结算要求九座位安全显示元数据且幂等重试参数一致() throws {
    let fixture = try pendingNineSeatSettlement()
    let metadata = try makeArchiveMetadata(tableName: "星河湾")
    let transactionID = try BusinessID("history-metadata")

    let first = try fixture.store.commitPendingHand(
        transactionID: transactionID,
        archiveMetadata: metadata
    )
    let retry = try fixture.store.commitPendingHand(
        transactionID: transactionID,
        archiveMetadata: metadata
    )

    #expect(first == retry)
    #expect(first.archiveMetadata == metadata)
}

@Test func 相同结算编号使用不同显示元数据会被拒绝() throws {
    let fixture = try pendingNineSeatSettlement()
    let transactionID = try BusinessID("history-conflict")
    _ = try fixture.store.commitPendingHand(
        transactionID: transactionID,
        archiveMetadata: makeArchiveMetadata(tableName: "星河湾")
    )

    #expect(throws: PokerSessionError.businessIDConflict) {
        try fixture.store.commitPendingHand(
            transactionID: transactionID,
            archiveMetadata: makeArchiveMetadata(tableName: "另一张桌")
        )
    }
}
```

在 `SettlementPipelineTests.swift` 增加：

```swift
@Test @MainActor func 结算保存冻结牌桌与九座位名称且重试复用同一元数据() async throws {
    let repository = FailOnceSessionRepository()
    let fixture = try await CoordinatorScenario.pendingSettlement(
        repository: repository,
        archiveMetadata: makeCoordinatorArchiveMetadata(tableName: "星河湾")
    )

    await fixture.coordinator.finishSettlement()
    #expect(fixture.coordinator.state.phase == .saveFailed)
    try await fixture.coordinator.retrySave()

    let stored = try #require(fixture.store.handRecords().first)
    #expect(stored.archiveMetadata?.tableDisplayName == "星河湾")
    #expect(stored.archiveMetadata?.seatDisplayNames.count == 9)
    #expect(stored.transactionID != nil)
    #expect(fixture.store.handRecords().count == 1)
    #expect(repository.attemptedBusinessIDs().count == 2)
}
```

在 `CashTableEntryTests.swift` 增加：

```swift
func testJoinBuildsArchiveMetadataFromSelectedTableAndFrozenProfiles() throws {
    let fixture = try AppSessionFixture()
    let profiles = try TableSeatProfileFactory.make(humanSeat: SeatID(rawValue: 0)!)

    try fixture.session.joinCashTable(
        fixture.table,
        buyIn: 16_000,
        autoTopUp: false,
        reduceMotion: true,
        seatProfiles: profiles
    )

    XCTAssertEqual(
        fixture.capturedArchiveMetadata?.tableDisplayName,
        fixture.table.name
    )
    XCTAssertEqual(
        fixture.capturedArchiveMetadata?.seatDisplayNames,
        Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.displayName) })
    )
}
```

- [ ] **步骤 2：运行聚焦测试确认 RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --package-path Packages/PokerCore \
  --filter '新结算要求九座位|相同结算编号使用不同显示元数据|结算保存冻结牌桌与九座位名称且重试复用同一元数据'
```

预期：编译失败，提示协调器初始化和结算没有 `archiveMetadata`。

- [ ] **步骤 3：实现协调器元数据边界**

在 `LocalPokerStore` 将旧结算入口替换为：

```swift
public func commitPendingHand(
    transactionID: BusinessID,
    archiveMetadata: HandArchiveMetadata
) throws -> StoredHandRecord
```

校验元数据座位集合和真人座位与当前 session 一致；创建记录时保存元数据。命中结算回执或既有 hand ID 时必须同时比较元数据，不同则抛出 `.businessIDConflict`。统一更新仓库中全部 `commitPendingHand(transactionID:)` 调用，让测试 helper 显式传入稳定元数据；不得保留会产生无元数据新记录的公开重载。

在协调器中新增：

```swift
private let archiveMetadata: HandArchiveMetadata
```

两个初始化入口都要求调用方传入元数据，并在初始化时验证：

```swift
guard Set(archiveMetadata.seatDisplayNames.keys) == Set(session.seats.map(\.id)),
      archiveMetadata.humanSeat == humanSeat,
      archiveMetadata.seatDisplayNames == Dictionary(
          uniqueKeysWithValues: seatProfiles.map { ($0.id, $0.displayName) }
      )
else { throw PokerCoordinatorError.missingObservation }
```

保存改为：

```swift
_ = try store.commitPendingHand(
    transactionID: transactionID,
    archiveMetadata: archiveMetadata
)
```

元数据在协调器初始化时冻结，后续 UI 模型或机器人设置变化不能改变本手重试参数。

- [ ] **步骤 4：在 AppSession 构造真实元数据**

把 `AppSessionDependencies.makeCoordinator` 签名扩展为：

```swift
let makeCoordinator: (
    _ store: LocalPokerStore,
    _ humanSeat: SeatID,
    _ profiles: [TableSeatProfile],
    _ archiveMetadata: HandArchiveMetadata,
    _ runtime: TableRuntimeDependencies
) throws -> CashTableCoordinator
```

在 `joinCashTable` 中使用已经保存到 `CashTableJoinAttempt` 的 table、request 和 profiles 创建：

```swift
let archiveMetadata = try HandArchiveMetadata(
    tableDisplayName: attempt.table.name,
    humanSeat: attempt.request.humanSeat,
    seatDisplayNames: Dictionary(
        uniqueKeysWithValues: attempt.profiles.map { ($0.id, $0.displayName) }
    )
)
```

将同一值传给协调器；重试 `cashTableJoinAttempt` 时不得重新生成名称。

- [ ] **步骤 5：运行协调器与应用聚焦测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --package-path Packages/PokerCore --filter PokerCoordinatorTests

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
  -only-testing:RiverClubTests/CashTableEntryTests CODE_SIGNING_ALLOWED=NO
```

预期：协调器与入桌测试全部通过，0 失败。

- [ ] **步骤 6：中文提交**

```bash
git add Packages/PokerCore/Sources/PokerSession/Store/LocalPokerStore.swift Packages/PokerCore/Sources/PokerCoordinator Packages/PokerCore/Tests/PokerSessionTests Packages/PokerCore/Tests/PokerCoordinatorTests RiverClub/App/AppSession.swift RiverClubTests/CashTableEntryTests.swift
git commit -m "feat: 在牌局结算中冻结存档显示信息"
```

---

### 任务 3：实现纯存档展示模型与安全结果推导

**文件：**

- 新建：`RiverClub/Features/History/HandHistoryPresentation.swift`
- 新建：`RiverClub/Features/History/HandHistoryViewState.swift`
- 新建：`RiverClubTests/HandHistoryPresentationTests.swift`
- 新建：`RiverClubTests/Support/HandHistoryPresentationTestSupport.swift`

**接口：**

- 消费：`StoredHandRecord`、`CompletedHandRecord`、`PotBuilder.awards(for:ranks:dealer:)`。
- 产出：

```swift
struct HandHistoryListItem: Identifiable, Equatable, Sendable
struct HandHistoryDetail: Identifiable, Equatable, Sendable
struct HandHistorySeatResult: Identifiable, Equatable, Sendable
struct HandHistoryPotResult: Identifiable, Equatable, Sendable
enum HandHistorySeatStatus: Equatable, Sendable
enum HandHistoryDateSelection: Equatable, Sendable
struct HandHistoryFilters: Equatable, Sendable
enum HandHistoryLoadState: Equatable, Sendable
struct HandHistoryViewState: Equatable, Sendable
enum HandHistoryPresentation {
    static func listItem(from record: StoredHandRecord) throws -> HandHistoryListItem
    static func detail(from record: StoredHandRecord) throws -> HandHistoryDetail
}

func makeHistoryRecord(
    foldedSeat: SeatID? = SeatID(rawValue: 3)!,
    humanSeat: SeatID = SeatID(rawValue: 0)!,
    archiveMetadata: HandArchiveMetadata?
) throws -> StoredHandRecord

func makeMultiPotHistoryRecord() throws -> StoredHandRecord
func makePresentationArchiveMetadata() throws -> HandArchiveMetadata
```

两个展示测试 helper 必须通过 PokerCore 的真实发牌、合法动作和结算流程构造经过验证的 `CompletedHandRecord`；不得直接修改引擎私有状态或用不满足底池不变量的手写对象。

- [ ] **步骤 1：写最终结果和旧记录降级失败测试**

在 `HandHistoryPresentationTests.swift` 增加：

```swift
final class HandHistoryPresentationTests: XCTestCase {
    func testFinalResultIncludesFoldedHoleCardsAndHumanDelta() throws {
        let record = try makeHistoryRecord(
            foldedSeat: SeatID(rawValue: 3)!,
            humanSeat: SeatID(rawValue: 0)!,
            archiveMetadata: makePresentationArchiveMetadata()
        )

        let detail = try HandHistoryPresentation.detail(from: record)

        XCTAssertEqual(detail.seats.count, 9)
        XCTAssertEqual(detail.seats.first { $0.id.rawValue == 3 }?.cards.count, 2)
        XCTAssertEqual(detail.seats.first { $0.id.rawValue == 3 }?.status, .folded)
        XCTAssertEqual(
            detail.seats.first { $0.id.rawValue == 0 }?.chipDelta,
            record.record.chipDeltas[SeatID(rawValue: 0)!]
        )
    }

    func testLegacyRecordUsesStableFallbackNames() throws {
        let record = try makeHistoryRecord(archiveMetadata: nil)

        let detail = try HandHistoryPresentation.detail(from: record)

        XCTAssertEqual(detail.tableName, "牌桌 \(record.table.rawValue)")
        XCTAssertEqual(detail.seats.map(\.displayName).first, "座位 1")
    }

    func testPotRowsRebuildPerPotWinnersAndOddChipAmounts() throws {
        let record = try makeMultiPotHistoryRecord()

        let detail = try HandHistoryPresentation.detail(from: record)

        XCTAssertEqual(detail.pots.count, record.record.pots.count)
        XCTAssertEqual(
            detail.pots.flatMap(\.amounts).reduce(0) { $0 + $1.value },
            record.record.awards.values.reduce(0) { $0 + $1.rawValue }
        )
    }
}
```

- [ ] **步骤 2：运行测试确认 RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
  -only-testing:RiverClubTests/HandHistoryPresentationTests CODE_SIGNING_ALLOWED=NO
```

预期：编译失败，提示所有存档展示类型不存在。

- [ ] **步骤 3：实现值类型和纯转换**

座位状态按以下固定优先级推导：

```swift
let foldedSeats = Set(
    record.record.actions.compactMap { action in
        action.action == .fold ? action.seat : nil
    }
)

let status: HandHistorySeatStatus
if record.record.awards[seat, default: Chips(rawValue: 0)!].rawValue > 0 {
    status = .winner
} else if foldedSeats.contains(seat) {
    status = .folded
} else if record.record.holeCardsBySeat[seat] != nil {
    status = .showdown
} else {
    status = .notDealt
}
```

玩家名和桌名固定降级：

```swift
let tableName = record.archiveMetadata?.tableDisplayName
    ?? "牌桌 \(record.table.rawValue)"
let displayName = record.archiveMetadata?.seatDisplayNames[seat]
    ?? "座位 \(seat.rawValue + 1)"
```

每个底池单独调用公开纯函数，保证平分和奇数筹码顺序与规则引擎一致：

```swift
let amounts = try PotBuilder.awards(
    for: [pot],
    ranks: record.record.handRanksBySeat,
    dealer: record.record.config.dealer
)
```

若底池只有一个 eligible 座位但 `handRanksBySeat` 为空，直接把整池给该座位；其他缺失排名视为损坏展示数据并抛出错误。所有底池行金额合计必须等于 `record.record.awards` 合计，否则展示转换失败。

- [ ] **步骤 4：实现日期选择到存储过滤器的纯映射**

`HandHistoryDateSelection` 固定为：

```swift
enum HandHistoryDateSelection: Equatable, Sendable {
    case all
    case today
    case lastSevenDays
    case custom(LocalDay)
}
```

新增纯函数：

```swift
static func storeFilter(
    filters: HandHistoryFilters,
    today: LocalDay,
    calendar: Calendar
) throws -> HandRecordFilter
```

`.today` 使用精确 `localDay`；`.lastSevenDays` 从 today 向前包含 6 个自然日；`.custom` 使用精确单日；`.all` 只保留 table。所有日期由 `LocalDay` 构造，不用当前时区重新解释已保存记录。

- [ ] **步骤 5：运行展示测试**

使用步骤 2 相同命令。预期：全部通过，0 失败。

- [ ] **步骤 6：中文提交**

```bash
git add RiverClub/Features/History/HandHistoryPresentation.swift RiverClub/Features/History/HandHistoryViewState.swift RiverClubTests/HandHistoryPresentationTests.swift RiverClubTests/Support/HandHistoryPresentationTestSupport.swift
git commit -m "feat: 实现牌局存档最终结果展示模型"
```

---

### 任务 4：接入 AppSession 唯一存储、筛选与独立路由

**文件：**

- 修改：`RiverClub/App/AppSession.swift`
- 修改：`RiverClub/App/AppRootView.swift`
- 修改：`RiverClub/DesignSystem/AppSidebar.swift`
- 修改：`RiverClubTests/AppSessionTests.swift`
- 新建：`RiverClubTests/HandHistorySessionTests.swift`
- 新建：`RiverClubTests/Support/HandHistoryAppTestSupport.swift`

**接口：**

- 消费：任务 3 的 `HandHistoryViewState` 和 `HandHistoryPresentation`。
- 产出：

```swift
func loadHandHistory()
func updateHandHistoryFilters(_ filters: HandHistoryFilters)
func selectHandHistory(id: HandID)
func closeHandHistoryDetail()
func requestDeleteHand(id: HandID)
func requestDeleteAllHistory()
func cancelHistoryDeletion()
func confirmHistoryDeletion() throws
```

- `AppRoute` 增加 `.tableBrowser`；`.tables` 保持侧边栏“我的牌局”。
- 测试支持产出：

```swift
@MainActor
struct HandHistoryAppFixture {
    let directory: URL
    let store: LocalPokerStore
    let session: AppSession

    static func withThreeRecords() throws -> Self
    static func withFailingDelete() throws -> Self
    static func withActiveReadySessionAndRecords() throws -> Self
}
```

三个工厂都使用唯一真实 `LocalPokerStore`，并在 RiverClub 测试 target 内复用同样的 `sitDown → startHand → 合法动作完成 → commitPendingHand` 流程；不能依赖另一个测试 target 的 helper，也不能直接伪造持久化状态。`withFailingDelete` 只把 `AppSessionDependencies.deleteHandRecord`、`deleteAllHandRecords` 替换为抛出 `.persistenceFailed` 的闭包，不创建第二个 store；`withActiveReadySessionAndRecords` 使用 store 的公开会话命令建立 ready 会话。

- [ ] **步骤 1：写路由、加载、组合筛选和错误失败测试**

在 `AppSessionTests.swift` 增加：

```swift
func testSidebarKeepsHistoryAndTableBrowserIsNotSidebarItem() {
    XCTAssertEqual(AppRoute.sidebarRoutes, [.lobby, .tournaments, .tables, .profile])
    XCTAssertFalse(AppRoute.sidebarRoutes.contains(.tableBrowser))
}
```

在 `HandHistorySessionTests.swift` 增加：

```swift
@MainActor
func testLoadingHistoryUsesTheSameStoreAndCurrentFilters() throws {
    let fixture = try HandHistoryAppFixture.withThreeRecords()
    fixture.session.open(.tables)
    fixture.session.updateHandHistoryFilters(
        HandHistoryFilters(
            date: .custom(try LocalDay("2027-01-12")),
            table: try TableID("table-a")
        )
    )

    fixture.session.loadHandHistory()

    XCTAssertEqual(fixture.session.handHistoryState.items.map(\.handNumber), [2])
    XCTAssertTrue(fixture.session.pokerStore === fixture.store)
}

@MainActor
func testHistoryReadFailureKeepsErrorAndRetryAction() throws {
    var dependencies = AppSessionDependencies.live
    dependencies.loadHandRecords = { _, _ in throw PokerSessionError.persistenceFailed }
    let fixture = try AppSessionFixture(dependencies: dependencies)

    fixture.session.loadHandHistory()

    XCTAssertEqual(
        fixture.session.handHistoryState.loadState,
        .failed("牌局存档读取失败，请重试。")
    )
}
```

- [ ] **步骤 2：运行测试确认 RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
  -only-testing:RiverClubTests/AppSessionTests \
  -only-testing:RiverClubTests/HandHistorySessionTests CODE_SIGNING_ALLOWED=NO
```

预期：编译失败，提示 `.tableBrowser`、`handHistoryState` 和历史动作不存在。

- [ ] **步骤 3：为 AppSessionDependencies 增加可测试历史闭包**

把 `AppSessionDependencies` 从依赖成员的隐式 memberwise init 改为显式 init，保留当前四个必需参数并增加默认闭包：

```swift
var loadHandRecords: (LocalPokerStore, HandRecordFilter) throws -> [StoredHandRecord]
var deleteHandRecord: (LocalPokerStore, HandID) throws -> Void
var deleteAllHandRecords: (LocalPokerStore) throws -> Void
var currentLocalDay: () -> LocalDay
```

live 默认实现：

```swift
loadHandRecords: { store, filter in store.handRecords(filter: filter) },
deleteHandRecord: { store, id in try store.deleteHand(id: id) },
deleteAllHandRecords: { store in
    try store.deleteAllHands(confirmation: .confirmed)
},
currentLocalDay: { AppSessionClock().currentDay }
```

闭包始终接收 `AppSession.pokerStore`，不能捕获或创建另一个 store。

- [ ] **步骤 4：实现可观察历史状态与路由**

在 `AppSession` 新增：

```swift
private(set) var handHistoryState = HandHistoryViewState()

func open(_ route: AppRoute) {
    self.route = route
    if route == .tables { loadHandHistory() }
}
```

加载步骤固定：`.loading` → 解析过滤器 → 从唯一 store 读取 → 纯转换 → `.loaded`；任何错误映射为 `.failed("牌局存档读取失败，请重试。")`，不得清空 store。

`AppRootView` 路由改为：

- `.tables` → `HandHistoryView`（任务 5 提供）。
- `.tableBrowser` → `TableListView`。
- 大厅 `onAllTables` → `session.open(.tableBrowser)`。

`tableBrowser` 使用同一带侧边栏壳，但侧边栏不选中任何项；买入取消返回 `tableBrowser`。

- [ ] **步骤 5：运行 AppSession 测试**

使用步骤 2 命令。预期：全部通过，0 失败。

- [ ] **步骤 6：中文提交**

```bash
git add RiverClub/App RiverClub/DesignSystem/AppSidebar.swift RiverClubTests/AppSessionTests.swift RiverClubTests/HandHistorySessionTests.swift
git commit -m "feat: 接入真实存档状态与独立牌桌浏览路由"
```

---

### 任务 5：实现横屏存档列表、筛选和最终结果详情

**文件：**

- 新建：`RiverClub/Features/History/HandHistoryView.swift`
- 新建：`RiverClub/Features/History/HandHistoryDetailView.swift`
- 新建：`RiverClubTests/HandHistoryLayoutTests.swift`
- 修改：`RiverClub/App/AppRootView.swift`
- 修改：`project.yml`

**接口：**

- 消费：任务 4 的 `AppSession.handHistoryState` 和历史动作。
- 产出：可访问性标识：
  - `history.list`
  - `history.filter.date`
  - `history.filter.table`
  - `history.row.<handID>`
  - `history.empty`
  - `history.filteredEmpty`
  - `history.retry`
  - `history.balance`
  - `history.detail`
  - `history.seat.0` 到 `history.seat.8`
  - `history.holeCard.<座位号>.0` 和 `history.holeCard.<座位号>.1`
  - `history.deleteOne`
  - `history.deleteAll`

- [ ] **步骤 1：写横屏布局与内容失败测试**

在 `HandHistoryLayoutTests.swift` 增加：

```swift
final class HandHistoryLayoutTests: XCTestCase {
    func testLandscapeHistoryKeepsFiltersAndRowsInsideSafeCanvas() {
        let layout = HandHistoryLayout.safeCanvas(width: 932, height: 424)

        XCTAssertEqual(layout.filterWidth, 220)
        XCTAssertGreaterThanOrEqual(layout.contentWidth, 640)
        XCTAssertGreaterThanOrEqual(layout.minimumRowHeight, 88)
    }

    func testDetailUsesNineUniqueSeatSlotsWithoutCardCompression() {
        let slots = HandHistoryDetailLayout.seatSlots(
            in: CGSize(width: 932, height: 424)
        )

        XCTAssertEqual(slots.count, 9)
        XCTAssertEqual(Set(slots.map(\.id)).count, 9)
        XCTAssertTrue(slots.allSatisfy { $0.cardSize.width >= 28 })
        XCTAssertTrue(slots.allSatisfy { $0.cardSize.height >= 40 })
    }
}
```

- [ ] **步骤 2：运行测试确认 RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
  -only-testing:RiverClubTests/HandHistoryLayoutTests CODE_SIGNING_ALLOWED=NO
```

预期：编译失败，提示布局和视图类型不存在。

- [ ] **步骤 3：实现列表和筛选区**

`HandHistoryView` 固定使用：

```swift
struct HandHistoryView: View {
    @Bindable var session: AppSession

    var body: some View {
        HStack(spacing: 16) {
            HandHistoryFilterPanel(
                filters: session.handHistoryState.filters,
                availableTables: session.handHistoryState.availableTables,
                onChange: session.updateHandHistoryFilters
            )
            .frame(width: 220)

            HandHistoryContent(
                state: session.handHistoryState,
                onSelect: session.selectHandHistory,
                onRetry: session.loadHandHistory
            )
        }
        .padding(20)
        .accessibilityIdentifier("history.list")
        .onAppear { session.loadHandHistory() }
    }
}
```

筛选面板顶部从 `session.chipBalance` 渲染只读余额文本并设置 `history.balance`，保证删除前后 UI 可以直接验证经济状态未变化。

加载骨架、无存档、筛选无结果和失败状态必须分别渲染；筛选无结果按钮把 filters 重置为 `.init(date: .all, table: nil)`。

列表卡片用 `HandHistoryListItem`，公共牌按实际数量显示；净变化必须显示 `+1,240`、`−600` 或 `0`，不能只用颜色表达。

- [ ] **步骤 4：实现九座位最终结果详情**

详情根视图使用 `HandHistoryDetail`，不得直接读取 store：

```swift
struct HandHistoryDetailView: View {
    let detail: HandHistoryDetail
    let onBack: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HandHistoryDetailHeader(detail: detail, onBack: onBack, onDelete: onDelete)
            HandHistoryCommunityCards(cards: detail.communityCards)
            HandHistorySeatGrid(seats: detail.seats)
            HandHistoryPotList(pots: detail.pots, returns: detail.uncalledReturns)
        }
        .padding(20)
        .accessibilityIdentifier("history.detail")
    }
}
```

每个有牌座位显示两张 `TableCardView` 明牌；`.notDealt` 显示“未参与”且不制造牌背。弃牌玩家仍显示真实最终牌并带“已弃牌”文字，因为该页面只消费完成记录。

- [ ] **步骤 5：接入根路由并运行布局测试**

`AppRootView` 的 `.tables` 分支传入同一个 `session`。运行步骤 2 命令，预期全部通过。

- [ ] **步骤 6：生成工程并执行通用 iOS 测试构建**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

预期：`TEST BUILD SUCCEEDED`。

- [ ] **步骤 7：中文提交**

```bash
git add RiverClub/Features/History RiverClub/App/AppRootView.swift RiverClubTests/HandHistoryLayoutTests.swift project.yml
git commit -m "feat: 实现横屏牌局存档列表与详情"
```

---

### 任务 6：实现二次确认删除与原子错误恢复

**文件：**

- 修改：`RiverClub/Features/History/HandHistoryView.swift`
- 修改：`RiverClub/Features/History/HandHistoryDetailView.swift`
- 修改：`RiverClub/Features/History/HandHistoryViewState.swift`
- 修改：`RiverClub/App/AppSession.swift`
- 修改：`RiverClubTests/HandHistorySessionTests.swift`
- 修改：`RiverClubTests/HandHistoryLayoutTests.swift`

**接口：**

- 消费：`LocalPokerStore.deleteHand(id:)`、`deleteAllHands(confirmation:)`。
- 产出：显式确认状态和安全删除动作。

- [ ] **步骤 1：写取消、成功、失败和不变量测试**

在 `HandHistorySessionTests.swift` 增加：

```swift
@MainActor
func testSingleDeleteRequiresConfirmationAndPreservesEconomyState() throws {
    let fixture = try HandHistoryAppFixture.withThreeRecords()
    fixture.session.loadHandHistory()
    let id = try XCTUnwrap(fixture.session.handHistoryState.items.first?.id)
    let balance = fixture.store.accountBalance
    let statistics = fixture.store.statistics

    fixture.session.requestDeleteHand(id: id)
    fixture.session.cancelHistoryDeletion()
    XCTAssertEqual(fixture.store.handRecords().count, 3)

    fixture.session.requestDeleteHand(id: id)
    try fixture.session.confirmHistoryDeletion()

    XCTAssertEqual(fixture.store.handRecords().count, 2)
    XCTAssertEqual(fixture.store.accountBalance, balance)
    XCTAssertEqual(fixture.store.statistics, statistics)
}

@MainActor
func testDeleteFailureKeepsListAndOffersSameRetry() throws {
    let fixture = try HandHistoryAppFixture.withFailingDelete()
    fixture.session.loadHandHistory()
    let before = fixture.session.handHistoryState.items
    let id = try XCTUnwrap(before.first?.id)

    fixture.session.requestDeleteHand(id: id)
    XCTAssertThrowsError(try fixture.session.confirmHistoryDeletion())

    XCTAssertEqual(fixture.session.handHistoryState.items, before)
    XCTAssertEqual(
        fixture.session.handHistoryState.deletionError,
        "牌局存档删除失败，请重试。"
    )
    XCTAssertEqual(fixture.session.handHistoryState.pendingDeletion, .hand(id))
}

@MainActor
func testDeleteAllRequiresExplicitConfirmationAndPreservesCurrentSession() throws {
    let fixture = try HandHistoryAppFixture.withActiveReadySessionAndRecords()
    let cashSession = fixture.store.cashSession

    fixture.session.requestDeleteAllHistory()
    try fixture.session.confirmHistoryDeletion()

    XCTAssertTrue(fixture.store.handRecords().isEmpty)
    XCTAssertEqual(fixture.store.cashSession, cashSession)
}
```

- [ ] **步骤 2：运行删除测试确认 RED**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
  -only-testing:RiverClubTests/HandHistorySessionTests CODE_SIGNING_ALLOWED=NO
```

预期：编译失败，提示删除确认状态和动作不存在。

- [ ] **步骤 3：实现显式删除状态机**

在 `HandHistoryViewState.swift` 增加：

```swift
enum HandHistoryPendingDeletion: Equatable, Sendable {
    case hand(HandID)
    case all
}

var pendingDeletion: HandHistoryPendingDeletion?
var deletionError: String?
```

固定动作语义：

- `requestDeleteHand` / `requestDeleteAllHistory` 只设置 pending，不写 store。
- `cancelHistoryDeletion` 清除 pending 和错误。
- `confirmHistoryDeletion` 根据 pending 调用任务 4 注入闭包。
- 成功后清除 pending、selection 和错误，再调用 `loadHandHistory()` 保留当前 filters。
- 失败时保留 pending、列表和 selection，设置中文错误并重新抛出。

- [ ] **步骤 4：实现两个二次确认弹窗**

单局文案包含 `牌桌名 · 日期 · 第 N 手`；全部清空文案明确“余额、统计和账本不会删除”。危险按钮使用 `role: .destructive` 并有以下标识：

- `history.confirmDeleteOne`
- `history.confirmDeleteAll`
- `history.cancelDelete`

确认弹窗不能通过普通卡片点击直接执行删除。

- [ ] **步骤 5：运行删除与布局测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
  -only-testing:RiverClubTests/HandHistorySessionTests \
  -only-testing:RiverClubTests/HandHistoryLayoutTests CODE_SIGNING_ALLOWED=NO
```

预期：全部通过，0 失败。

- [ ] **步骤 6：中文提交**

```bash
git add RiverClub/Features/History RiverClub/App/AppSession.swift RiverClubTests/HandHistorySessionTests.swift RiverClubTests/HandHistoryLayoutTests.swift
git commit -m "feat: 实现牌局存档安全删除与错误恢复"
```

---

### 任务 7：完成核心 UI 闭环、边界加固与中文文档

**文件：**

- 新建：`RiverClubUITests/HandHistoryFlowUITests.swift`
- 修改：`RiverClubUITests/CoreFlowUITests.swift`
- 修改：`RiverClub/App/RiverClubApp.swift`
- 修改：`RiverClub/App/AppSession.swift`
- 修改：`Packages/PokerCore/Tests/PokerSessionPublicAPITests/PokerSessionBoundaryTests.swift`
- 修改：`Packages/PokerCore/Tests/PokerCoordinatorPublicAPITests/PokerCoordinatorPublicAPITests.swift`
- 修改：`README.md`
- 修改：`project.yml`

**接口：**

- 消费：任务 1–6 的全部公开接口和可访问性标识。
- 产出：真实存档第一版可交付闭环。

- [ ] **步骤 1：增加存档安全负向编译探针**

沿用现有普通 import typecheck 工具，确认新增存档接口不能访问：

```swift
_ = storedRecord.record.deck
_ = storedRecord.record.seed
_ = storedRecord.record.checkpoint
_ = storedRecord.archiveMetadata?.botSettings
_ = storedRecord.archiveMetadata?.decisionModel
_ = store.pendingShowdownObservation
```

控制源码必须先编译成功；每个探针必须同时匹配目标成员名和“无成员/不可访问”，不能因 `no such module` 或其他无关错误假通过。

- [ ] **步骤 2：实现核心存档 UI 测试**

`HandHistoryFlowUITests` 使用确定性 UI 测试存储和既有快速动画参数。先扩展 UI 测试启动逻辑：

- `-uiTesting -uiTestingImmediatePoker -resetHistoryStore`：首次流程前删除固定测试目录并建立新 store。
- `-uiTesting -uiTestingImmediatePoker -openHistory`：复用同一固定测试目录，不删除，创建 `AppSession` 后调用 `continueAsGuest()` 和 `open(.tables)`。
- 两种模式都只能控制测试目录和初始路由，不能直接插入或伪造完成记录。

```swift
func testCompletedHandAppearsWithFoldedCardsAndCanBeDeleted() throws {
    let app = XCUIApplication()
    app.launchArguments = [
        "-uiTesting",
        "-uiTestingImmediatePoker",
        "-resetHistoryStore"
    ]
    app.launch()

    app.buttons["login.guest"].tap()
    app.buttons["lobby.allTables"].tap()
    app.buttons["tableRow.10000000-0000-0000-0000-000000000001"].tap()
    app.sliders["buyIn.slider"].adjust(toNormalizedSliderPosition: 0.25)
    app.buttons["buyIn.confirm"].tap()
    XCTAssertTrue(app.buttons["action.fold"].waitForExistence(timeout: 10))
    app.buttons["action.fold"].tap()
    XCTAssertTrue(app.buttons["action.nextHand"].waitForExistence(timeout: 15))

    app.terminate()
    app.launchArguments = [
        "-uiTesting",
        "-uiTestingImmediatePoker",
        "-openHistory"
    ]
    app.launch()

    let balanceBefore = app.staticTexts["history.balance"].label
    let row = app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH 'history.row.'")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.tap()

    XCTAssertTrue(app.otherElements["history.detail"].exists)
    XCTAssertEqual(
        app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.seat.'")
        ).count,
        9
    )
    XCTAssertGreaterThan(
        app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.holeCard.'")
        ).count,
        2
    )

    app.buttons["history.deleteOne"].tap()
    app.buttons["history.confirmDeleteOne"].tap()
    XCTAssertTrue(app.otherElements["history.empty"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["history.balance"].label, balanceBefore)
}
```

沉浸式牌桌没有侧边栏，因此测试必须按上述方式在真实保存后重启并复用同一测试 store；不得重新开放牌桌返回按钮。

- [ ] **步骤 3：运行全量 Swift Package 测试**

```bash
HOME=/private/tmp/riverclub-history-home \
CLANG_MODULE_CACHE_PATH=/private/tmp/riverclub-history-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/riverclub-history-swiftpm-cache \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --package-path Packages/PokerCore --no-parallel
```

预期：所有 PokerCore、PokerSession、PokerBot、PokerCoordinator 和公开边界测试通过，0 失败。

- [ ] **步骤 4：运行 RiverClub 单元和存档 UI 测试**

先用 `xcrun simctl list devices available` 确认 Pro Max UDID。若 `86B6F41B-B5EA-4267-8FA3-0C92481DE8E8` 失效，只能替换为同一输出中实际可用的最新 Pro Max，并在交付中记录。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
  -only-testing:RiverClubTests CODE_SIGNING_ALLOWED=NO

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
  -only-testing:RiverClubUITests/CoreFlowUITests \
  -only-testing:RiverClubUITests/HandHistoryFlowUITests CODE_SIGNING_ALLOWED=NO
```

预期：全部通过，0 失败。

- [ ] **步骤 5：重新生成工程并执行通用 iOS 构建**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

预期：`TEST BUILD SUCCEEDED`。

- [ ] **步骤 6：更新中文 README**

删除“仅 UI 原型、没有规则引擎、使用固定牌桌数据完成牌局”的过时描述，准确写明：

- 本地 PokerCore 规则引擎与普通桌可玩闭环已经接入。
- 机器人只依据自身安全观察决策。
- 已完成牌局永久保存在 Application Support，可在“我的牌局”查看最终结果和所有最终底牌。
- 进行中牌局仍隐藏对手底牌。
- 娱乐筹码无现金价值；仍无实时多人网络、真钱充值提现、云同步和生产身份服务。

- [ ] **步骤 7：检查差异并独立复审**

```bash
git diff --check
git status --short
```

独立复审必须逐项检查：

- 旧存档兼容，不静默重置。
- 新元数据幂等且只含安全显示文本。
- 弃牌者最终牌只在完成存档详情显示。
- 日期/牌桌组合筛选稳定。
- 单局和全部删除不修改经济与永久身份。
- “我的牌局”和“全部牌桌”路由不再冲突。
- UI 横屏无牌面、头像、筛选区或弹窗遮挡。
- CoreFlow 既有买入到下一手路径无回归。

修复所有 Critical 和 Important 后重新运行步骤 3–5。

- [ ] **步骤 8：中文提交最终验收**

```bash
git add Packages/PokerCore/Tests RiverClub/App/RiverClubApp.swift RiverClub/App/AppSession.swift RiverClubUITests README.md project.yml
git commit -m "test: 验证真实牌局存档与隐藏信息边界"
```

## 最终交付证据

交付时必须报告：

- Swift Package 测试总数与失败数。
- RiverClub 单元测试与 CoreFlow/HandHistory UI 测试结果。
- 通用 iOS `build-for-testing` 结果。
- 实际使用的 Pro Max 模拟器型号、系统和 UDID。
- 从真实结算保存到列表、详情、弃牌底牌、筛选和删除的端到端结果。
- 单局与全部删除前后余额、账本、统计、当前会话和永久身份不变量证据。
- 普通导入隐藏信息负向编译探针结果。
- iPhone 16 Pro Max 真机视觉验收是否完成；未完成时明确保留。
- `git status --short` 为空，所有新增 Git 提交均为中文。
