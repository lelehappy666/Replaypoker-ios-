# River Club 牌桌身份、筹码、派彩与大厅视觉升级实施计划

> **面向智能开发代理：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，严格按任务逐项实施。步骤使用复选框跟踪。

**目标：** 完成融合式大厅背景、美元余额、真人机器人身份池、标准牌面、多色筹码下注、按赢家聚合派彩和顺时针牌桌表现。

**架构：** 机器人身份作为独立展示目录，由 `AppSession` 在每次重新入桌时抽取并冻结到座位资料；大厅用同一目录生成稳定预览。牌桌视图继续只消费 `TableViewState`；协调器只调整动画映射，把多个底池奖励按赢家聚合，不改变规则引擎的结算结果。

**技术栈：** Swift 6、SwiftUI、Observation、Swift Testing、XCTest、Swift Package Manager、Xcode 26。

## 全局约束

- 所有文档、规格、计划和交付说明使用中文；所有 Git/GitHub 提交使用中文。
- 直接在 `main` 工作；应用全程横屏，以 iPhone 16 Pro Max 安全区域为设计目标。
- 生产代码必须先写失败测试并观察正确失败。
- 头像与名字只属于展示层，不进入机器人决策输入。
- 不增加真钱充值、提现、兑换或支付能力；美元符号只是界面计量符号。
- 不修改主池、边池、合法行动者和胜负计算规则。

---

## 文件结构

### 新建

- `RiverClub/Models/RobotIdentity.swift`：二十四人身份目录、随机抽取和大厅稳定预览。
- `RiverClub/DesignSystem/RobotAvatarView.swift`：头像和加载失败占位。
- `RiverClub/DesignSystem/CasinoChipStackView.swift`：面额拆分、筹码和堆叠视图。
- `RiverClub/Features/Lobby/LobbyBackground.swift`：背景图、渐变和暗角。
- `RiverClub/Resources/Assets.xcassets/`：大厅背景和二十四组头像。
- `RiverClub/Resources/RobotAvatarLicenses.json`：头像来源、作者和许可清单。
- `RiverClubTests/RobotIdentityTests.swift`、`RiverClubTests/CasinoChipStackTests.swift`。

### 修改

- `RiverClub.xcodeproj/project.pbxproj`：注册新代码、测试和资源。
- `Packages/PokerCore/Sources/PokerCoordinator/Domain/TableViewState.swift`：座位资料增加头像标识。
- `Packages/PokerCore/Sources/PokerSession/History/HandHistory.swift`：存档增加可选头像映射。
- `RiverClub/App/AppSession.swift`：重新入桌抽取身份，同桌多手复用。
- `RiverClub/Features/Lobby/LobbyView.swift`、`TableListView.swift`、`ChipBalancePill.swift`：大厅视觉和美元格式。
- `RiverClub/Features/Table/TableCardView.swift`、`PokerSeatView.swift`、`PokerTableView.swift`：牌面、头像、下注和公共牌。
- `Packages/PokerCore/Sources/PokerCoordinator/Animation/TableAnimationEvent.swift`、`Cash/CashTableAnimationMapper.swift`、`Cash/CashTableCoordinator.swift`：聚合派彩。
- 对应的包测试、应用单元测试和 UI 测试。

---

### 任务 1：建立机器人身份目录与头像资源

**文件：** 新建 `RobotIdentity.swift`、`RobotAvatarView.swift`、资源目录和 `RobotIdentityTests.swift`；修改 `project.pbxproj`。

**接口：** 产出 `RobotIdentity`、`RobotIdentityCatalog.all`、`draw(count:using:)`、`preview(for:count:)` 和 `RobotAvatarView`。

- [ ] **步骤 1：写失败测试**

```swift
@MainActor
final class RobotIdentityTests: XCTestCase {
    func testCatalogContainsTwentyFourUniqueBoundIdentities() {
        let values = RobotIdentityCatalog.all
        XCTAssertEqual(values.count, 24)
        XCTAssertEqual(Set(values.map(\.id)).count, 24)
        XCTAssertEqual(Set(values.map(\.displayName)).count, 24)
        XCTAssertEqual(Set(values.map(\.avatarAssetName)).count, 24)
        XCTAssertTrue(values.allSatisfy { !$0.sourceURL.absoluteString.isEmpty })
    }

    func testDrawReturnsEightUniqueIdentitiesDeterministically() {
        var a = SeededIdentityGenerator(seed: 41)
        var b = SeededIdentityGenerator(seed: 41)
        let left = RobotIdentityCatalog.draw(count: 8, using: &a)
        let right = RobotIdentityCatalog.draw(count: 8, using: &b)
        XCTAssertEqual(left, right)
        XCTAssertEqual(Set(left.map(\.id)).count, 8)
    }
}
```

- [ ] **步骤 2：运行并确认因目录类型不存在而失败**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubTests/RobotIdentityTests
```

- [ ] **步骤 3：实现模型和固定目录**

```swift
struct RobotIdentity: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let avatarAssetName: String
    let sourceURL: URL
    let photographer: String
    let accessibilityDescription: String
}

enum RobotIdentityCatalog {
    static let names = [
        "林墨", "青屿", "空山", "云雀", "晨星", "海盐", "玖未", "深野",
        "沐川", "苏禾", "江屿", "若岚", "安澜", "迟野", "星遥", "砚舟",
        "南乔", "景行", "清和", "知夏", "归晚", "云川", "昭月", "远山",
    ]

    static func draw<R: RandomNumberGenerator>(count: Int, using generator: inout R) -> [RobotIdentity] {
        Array(all.shuffled(using: &generator).prefix(count))
    }
}
```

每张头像使用不小于 512×512 的成人真人头肩肖像。`RobotAvatarLicenses.json` 对每个资源记录 Pexels 页面地址、作者和 `Pexels License`；不使用名人、品牌人物或未成年人。

- [ ] **步骤 4：实现头像组件**

```swift
struct RobotAvatarView: View {
    let imageName: String?
    let fallbackText: String
    let size: CGFloat

    var body: some View {
        Group {
            if let imageName, UIImage(named: imageName) != nil {
                Image(imageName).resizable().scaledToFill()
            } else {
                Text(String(fallbackText.prefix(2))).font(.caption.bold())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(RCTheme.gold.opacity(0.72), lineWidth: 1) }
    }
}
```

- [ ] **步骤 5：运行 2 项身份测试并提交**

```bash
git add RiverClub/Models/RobotIdentity.swift RiverClub/DesignSystem/RobotAvatarView.swift RiverClub/Resources RiverClubTests/RobotIdentityTests.swift RiverClub.xcodeproj/project.pbxproj
git commit -m "feat: 建立真人机器人身份与头像目录"
```

---

### 任务 2：把身份绑定到重新入桌生命周期和存档

**文件：** 修改 `TableViewState.swift`、`HandHistory.swift`、`CashTableCoordinator.swift`、`AppSession.swift`、`CashTableEntryTests.swift` 和存档恢复测试。

**接口：** `TableSeatProfile.init(id:displayName:avatarAssetName:)`、`TableSeatState.avatarAssetName`、`HandArchiveMetadata.seatAvatarAssetNames`、`AppSessionDependencies.makeSeatProfiles`。

- [ ] **步骤 1：写失败测试**

```swift
func testNewEntryDrawsProfilesOnceAndRetryReusesThem() async throws {
    var draws = 0
    let dependencies = makeDependencies(makeSeatProfiles: { humanSeat in
        draws += 1
        return try profileFixture(humanSeat: humanSeat, generation: draws)
    })
    let session = makeSession(dependencies: dependencies)
    try await session.joinCashTable(table, buyIn: 8_000, autoTopUp: false)
    XCTAssertEqual(draws, 1)
    await session.retryTableStartup()
    XCTAssertEqual(draws, 1)
}
```

另写两项：成功离桌后再次入桌 `draws == 2`；连续 `.nextHand` 后 `draws == 1`。

- [ ] **步骤 2：运行并确认失败原因是身份提供器尚未注入**

- [ ] **步骤 3：扩展可选头像字段并兼容旧数据**

```swift
public struct TableSeatProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: SeatID
    public let displayName: String
    public let avatarAssetName: String?

    public init(id: SeatID, displayName: String, avatarAssetName: String? = nil) throws {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatar = avatarAssetName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, avatar != "" else {
            throw PokerCoordinatorError.missingObservation
        }
        self.id = id
        self.displayName = name
        self.avatarAssetName = avatar
    }
}
```

头像字段统一使用 `decodeIfPresent`；旧存档无头像时保持 `nil`，显示首字占位，不回写旧文件。

- [ ] **步骤 4：在创建 `CashTableJoinAttempt` 时只抽取一次身份**

```swift
let profiles = try dependencies.makeSeatProfiles(request.humanSeat)
cashTableJoinAttempt = CashTableJoinAttempt(
    table: table, buyIn: buyIn, autoTopUp: autoTopUp,
    request: request, businessID: businessID, profiles: profiles
)
```

生产提供器随机抽八人绑定座位 0...7；座位 8 固定为 `RiverAce`。重试和下一手继续使用已保存的 `profiles`。

- [ ] **步骤 5：运行核心恢复测试和 `CashTableEntryTests`，然后提交**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter SessionRecoveryTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubTests/CashTableEntryTests
git add Packages/PokerCore RiverClub/App/AppSession.swift RiverClubTests/CashTableEntryTests.swift
git commit -m "feat: 按重新入桌冻结机器人身份"
```

---

### 任务 3：实现融合式大厅背景、美元金额与桌友头像

**文件：** 新建 `LobbyBackground.swift`；修改 `LobbyView.swift`、`TableListView.swift`、`ChipBalancePill.swift`、大厅单元测试和 `LandscapeLayoutUITests.swift`。

**接口：** `EntertainmentAmountFormatter.string(_:)`、`LobbyBackground`、`RobotIdentityCatalog.preview(for:count:)`。

- [ ] **步骤 1：写失败测试**

```swift
func testEntertainmentAmountsUseDollarSymbolButBlindLevelsDoNot() {
    XCTAssertEqual(EntertainmentAmountFormatter.string(88_500), "$88,500")
    XCTAssertEqual(PokerTablePresentation.blinds(small: 100, big: 200), "100 / 200")
}

func testLobbyPreviewIsStableAndUniquePerTable() {
    let first = RobotIdentityCatalog.preview(for: table.id, count: 6)
    let second = RobotIdentityCatalog.preview(for: table.id, count: 6)
    XCTAssertEqual(first, second)
    XCTAssertEqual(Set(first.map(\.id)).count, 6)
}
```

- [ ] **步骤 2：运行并确认格式器和预览接口不存在**

- [ ] **步骤 3：实现格式器和融合背景**

```swift
enum EntertainmentAmountFormatter {
    static func string(_ value: Int) -> String { "$\(value.formatted())" }
}

struct LobbyBackground: View {
    var body: some View {
        Image("lobby-background").resizable().scaledToFill()
            .overlay(RCTheme.background.opacity(0.80))
            .overlay {
                RadialGradient(
                    colors: [RCTheme.surfaceRaised.opacity(0.36), .black.opacity(0.54)],
                    center: .center, startRadius: 20, endRadius: 620
                )
            }
            .ignoresSafeArea().accessibilityHidden(true)
    }
}
```

- [ ] **步骤 4：推荐桌加入六个头像，热门区改为两个等宽卡片**

背景使用已确认的深墨绿赌场氛围资产；卡片使用 `RCTheme.surface.opacity(0.88)`、细金边和统一圆角。顶栏余额只显示 `$` 文本，不显示筹码图标。

- [ ] **步骤 5：UI 测试验证 `$88,500`、头像和热门桌全部位于窗口内，然后提交**

```bash
git add RiverClub/Features/Lobby RiverClub/DesignSystem/ChipBalancePill.swift RiverClubTests RiverClubUITests RiverClub.xcodeproj/project.pbxproj
git commit -m "feat: 融合大厅背景并展示真人桌友"
```

---

### 任务 4：建立真实多面额赌场筹码组件

**文件：** 新建 `CasinoChipStackView.swift` 和 `CasinoChipStackTests.swift`；修改 `project.pbxproj`。

**接口：** `CasinoChipDenomination`、`CasinoChipBreakdown.make(amount:maximumVisibleChips:)`、`CasinoChipStackView(amount:scale:)`。

- [ ] **步骤 1：写失败测试**

```swift
func testSixHundredUsesPurpleAndBlackCasinoChips() {
    XCTAssertEqual(
        CasinoChipBreakdown.make(amount: 600, maximumVisibleChips: 8),
        [.fiveHundred, .oneHundred]
    )
}

func testLargePotKeepsVisualChipCountBounded() {
    XCTAssertLessThanOrEqual(
        CasinoChipBreakdown.make(amount: 88_500, maximumVisibleChips: 12).count, 12
    )
}
```

- [ ] **步骤 2：运行并确认类型不存在**

- [ ] **步骤 3：实现赌场面额颜色**

```swift
enum CasinoChipDenomination: Int, CaseIterable {
    case one = 1, five = 5, twentyFive = 25
    case oneHundred = 100, fiveHundred = 500, oneThousand = 1_000

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
}
```

单枚筹码表现椭圆主体、双圆环、四组边缘色块和侧面厚度；堆叠按 3 点偏移。大数额保留最高面额组合，显示数量不超过参数上限。

- [ ] **步骤 4：运行测试并提交**

```bash
git add RiverClub/DesignSystem/CasinoChipStackView.swift RiverClubTests/CasinoChipStackTests.swift RiverClub.xcodeproj/project.pbxproj
git commit -m "feat: 新增多面额赌场筹码组件"
```

---

### 任务 5：重做牌桌座位、牌面、公共牌槽与下注筹码

**文件：** 修改 `TableCardView.swift`、`PokerSeatView.swift`、`PokerTableView.swift`、`PokerTableLayoutTests.swift` 和 `LandscapeLayoutUITests.swift`。

**接口：** `communityCardFrames(for:)`、`betPosition(forSeatAt:canvas:)`、`cardAspectRatio`、`holeCardSpacing`。

- [ ] **步骤 1：写布局失败测试**

```swift
func testCardsUsePokerRatioAndPositiveGap() {
    XCTAssertEqual(PokerTableLayout.cardAspectRatio, 34.0 / 46.0, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(PokerTableLayout.holeCardSpacing, 4)
}

func testFiveCommunitySlotsRemainClear() {
    for canvas in canvases {
        let slots = PokerTableLayout.communityCardFrames(for: canvas)
        XCTAssertEqual(slots.count, 5)
        for seat in PokerTableLayout.seatFrames(for: canvas) {
            XCTAssertTrue(slots.allSatisfy { !$0.intersects(seat) })
        }
    }
}
```

另测每个 `betPosition` 位于座位与桌心之间，且不进入公共牌和操作区。

- [ ] **步骤 2：运行并观察牌距、牌槽和下注位置测试失败**

- [ ] **步骤 3：实现标准牌面和顺时针外缘座位**

本人约 `46×62`，机器人约 `38×52`，公共牌约 `46×62`；全部使用 `34/46` 比例和至少 4 点正间距。本人固定底部中央，座位 0...7 沿外缘顺时针排列。

- [ ] **步骤 4：接入真人头像并拆开状态标签**

座位改为“牌、头像、姓名、剩余数值、状态”的轻量组合。状态位于数值下方；弃牌只降低牌和头像透明度，状态保持满对比度。

- [ ] **步骤 5：渲染五张公共牌槽与当前下注**

```swift
ForEach(0..<5, id: \.self) { index in
    Group {
        if state.communityCards.indices.contains(index) {
            TableCardView(card: state.communityCards[index])
        } else {
            RoundedRectangle(cornerRadius: 6)
                .stroke(RCTheme.gold.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [4]))
        }
    }
    .frame(width: 46, height: 62)
}
```

对 `committedThisStreet.rawValue > 0` 的座位，在座位朝向桌心的位置显示 `CasinoChipStackView` 和普通数字；换街归零后下注堆消失，中央底池显示混合筹码堆。

- [ ] **步骤 6：运行布局和横屏 UI 测试并提交**

```bash
git add RiverClub/Features/Table RiverClubTests/PokerTableLayoutTests.swift RiverClubUITests/LandscapeLayoutUITests.swift
git commit -m "feat: 重做牌桌座位牌面与下注筹码"
```

---

### 任务 6：把底池奖励按赢家聚合为一次派彩

**文件：** 修改 `TableAnimationEvent.swift`、`CashTableAnimationMapper.swift`、`CashTableCoordinator.swift`、`TableAnimationTests.swift`、`TableInteractionState.swift`、`PokerTableView.swift` 和交互测试。

**接口：** `TableAnimationEvent.awardPot(seat:amount:)`；`CashTableAnimationMapper.map(_:humanSeat:humanCards:beforeAction:dealer:)`。

- [ ] **步骤 1：写聚合失败测试**

```swift
@Test func 同一赢家多个底池只产生一次派彩() throws {
    let winner = try SeatID(4)
    let mapped = try mapAwards([
        .potAwarded(potIndex: 0, winners: [winner], amounts: [winner: try Chips(600)]),
        .potAwarded(potIndex: 1, winners: [winner], amounts: [winner: try Chips(200)]),
    ], dealer: try SeatID(1))
    #expect(mapped.filter { $0.kind == .awardPot } == [
        .awardPot(seat: winner, amount: try Chips(800)),
    ])
}
```

再写双赢家测试：庄家为座位 7 时，座位 8 先于座位 2；每位赢家只有一个事件，奖励总和保持不变。

- [ ] **步骤 2：运行并确认旧映射器按底池重复派彩**

- [ ] **步骤 3：实现汇总、溢出保护和顺时针排序**

```swift
let orderedWinners = totals.keys.sorted {
    clockwiseDistance(after: dealer, to: $0)
        < clockwiseDistance(after: dealer, to: $1)
}
```

每次金额相加使用 `addingReportingOverflow`，溢出抛出 `.chipArithmeticOverflow`。每位赢家只输出一组 `.awardPot` 和 `.highlightWinner`；其他动画保持原顺序。

- [ ] **步骤 4：SwiftUI 用赢家总额渲染一次筹码移动和一次公告**

减少动态时跳过移动轨迹，但公告和金额更新仍只发生一次。

- [ ] **步骤 5：运行协调器和应用交互测试并提交**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --filter TableAnimationTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubTests/PokerTableInteractionTests
git add Packages/PokerCore RiverClub/Features/Table RiverClubTests/PokerTableInteractionTests.swift
git commit -m "feat: 按赢家汇总并一次完成派彩"
```

---

### 任务 7：验证顺时针规则、全流程和设备构建

**文件：** 修改 `PokerTableLayoutTests.swift`、`CoreFlowUITests.swift`、`LandscapeLayoutUITests.swift` 和 `HandHistoryFlowUITests.swift`。

- [ ] **步骤 1：增加顺时针测试**

验证座位 0...8 的极角顺序、本人固定底部中央、庄家从 8 到 0 环回，以及弃牌/全下座位被规则层跳过时视觉不逆时针。

- [ ] **步骤 2：增加身份生命周期 UI 测试**

第一次入桌记录八个 `table.botAvatar.*` 标签；点击下一手后保持一致；离桌重新进入后，使用固定 UI 测试种子验证身份集合切换且组内无重复。

- [ ] **步骤 3：增加派彩次数 UI 断言**

固定单赢家牌局只出现一次 `table.winnerAnnouncement`；固定双赢家牌局按顺时针出现两次公告，每个名字只出现一次。

- [ ] **步骤 4：运行完整核心测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/PokerCore --scratch-path /private/tmp/riverclub-pokercore-final
```

- [ ] **步骤 5：运行完整应用测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubTests -derivedDataPath /private/tmp/riverclub-unit-identity-final
```

- [ ] **步骤 6：运行关键横屏 UI 流程**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubUITests/CoreFlowUITests -only-testing:RiverClubUITests/LandscapeLayoutUITests -only-testing:RiverClubUITests/HandHistoryFlowUITests -derivedDataPath /private/tmp/riverclub-ui-identity-final
```

- [ ] **步骤 7：完成真实 iPhone 通用目标构建**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/riverclub-device-identity-final CODE_SIGNING_ALLOWED=NO
```

预期：核心、应用和 UI 测试均为 0 失败，设备构建显示 `TEST BUILD SUCCEEDED`。

- [ ] **步骤 8：检查并提交最终测试**

```bash
git diff --check
git status --short
git add RiverClubTests RiverClubUITests
git commit -m "test: 验证真人身份筹码派彩与顺时针流程"
```

---

## 完成检查表

- [ ] 二十四组真人头像、中文名字和许可记录一一绑定。
- [ ] 每次重新入桌抽取八个不重复身份，同桌下一手不更换。
- [ ] 大厅背景与 UI 融合，余额使用美元符号，盲注不增加美元符号。
- [ ] 九座位沿桌边顺时针分散，状态不覆盖数值。
- [ ] 手牌使用标准比例、正间距和完整牌边；中央五张公共牌槽完整。
- [ ] 玩家当前下注显示在座位前方，换街后汇入中央底池。
- [ ] 筹码使用白、红、绿、黑、紫、橙真实面额配色和堆叠效果。
- [ ] 单赢家只派彩一次，多赢家每人只派彩一次且总额准确。
- [ ] 庄家、发牌和行动视觉顺序保持顺时针。
- [ ] 核心测试、应用测试、关键 UI 流程和设备构建全部通过。
