# River Club SwiftUI UI 原型实施计划

> **面向执行代理：** 必须使用子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans，逐项实施本计划。各步骤使用复选框（`- [ ]`）语法进行跟踪。

**目标：** 使用本地固定数据和确定性 UI 状态，构建一个可运行、仅支持横屏的 SwiftUI 原型，覆盖已批准的七个 River Club 界面。

**架构：** 使用一个小型、按功能组织的 SwiftUI 应用，包含一个可观察的 `AppSession`、基于协议的本地仓库，以及可复用的设计系统组件。原型不包含扑克规则引擎或网络功能；按钮驱动确定性的本地状态，使每个已批准流程都能独立审查和测试。

**技术栈：** Swift 6、SwiftUI、Observation、XCTest/XCUITest、Xcode 26、iOS 18+，以及仅用于开发阶段的项目生成器 XcodeGen 2.43+。

## 全局约束

- 以 iPhone 16 Pro Max 为目标设备，且仅支持向左和向右横屏。
- 部署目标为 iOS 18.0。
- 仅使用不具现金价值、不可提现、不可兑换且不含真实货币符号的娱乐筹码。
- 首个版本仅支持无限注德州扑克。
- 满桌时必须准确显示九个座位：八名对手和本地玩家。
- 本地玩家头像须保持圆形，并防止水平方向压缩。
- 奖池放在公共牌下方，筹码堆放在奖池下方。
- 遵守灵动岛和主屏幕指示条的安全区域。
- 使用原创的 River Club 名称和素材；不得复制 Replay Poker 的商标、徽标、插图或专有视觉素材。
- 运行时依赖必须保持为 Apple 原生框架；XcodeGen 仅用于开发阶段。
- 本计划使用模拟数据实现 UI 行为，不实现扑克规则引擎、实时多人游戏、身份认证服务器或筹码经济后端。

---

## 规划的文件结构

```text
project.yml                                  XcodeGen 项目定义
RiverClub/App/RiverClubApp.swift             应用入口和屏幕方向策略
RiverClub/App/AppRootView.swift              会话路由和根视图组合
RiverClub/App/AppSession.swift               可观察的导航/会话状态
RiverClub/DesignSystem/Theme.swift           颜色、间距、字体、阴影
RiverClub/DesignSystem/AppSidebar.swift      共用横屏导航
RiverClub/DesignSystem/ChipBalancePill.swift 共用虚拟筹码显示
RiverClub/Models/PokerModels.swift           UI 领域模型
RiverClub/Services/PokerRepository.swift     数据契约
RiverClub/Services/MockPokerRepository.swift 确定性固定数据
RiverClub/Features/Auth/LoginView.swift       登录界面
RiverClub/Features/Lobby/LobbyView.swift      精选和快速加入大厅
RiverClub/Features/Lobby/TableListView.swift 可筛选的牌桌列表
RiverClub/Features/Lobby/BuyInSheet.swift     买入确认
RiverClub/Features/Table/PokerTableView.swift 九座扑克桌
RiverClub/Features/Table/PokerSeatView.swift 可复用座位展示
RiverClub/Features/Table/BetControlBar.swift 下注预设和滑块
RiverClub/Features/Tournaments/TournamentsView.swift 锦标赛卡片
RiverClub/Features/Profile/ProfileView.swift 个人资料和设置链接
RiverClub/Features/Shared/LoadableContent.swift 加载/空数据/离线/错误状态
RiverClubTests/AppSessionTests.swift          导航/会话单元测试
RiverClubTests/MockPokerRepositoryTests.swift 固定数据和座位数量测试
RiverClubTests/BuyInTests.swift               买入验证测试
RiverClubUITests/CoreFlowUITests.swift        端到端 UI 流程
RiverClubUITests/LandscapeLayoutUITests.swift 横屏布局和无障碍检查
```

## 任务 1：搭建横屏 SwiftUI 应用

**文件：**
- 创建：`project.yml`
- 创建：`RiverClub/App/RiverClubApp.swift`
- 创建：`RiverClub/App/AppRootView.swift`
- 创建：`RiverClub/App/AppSession.swift`
- 创建：`RiverClubTests/AppSessionTests.swift`

**接口：**
- 产出：`enum AppRoute`、`@Observable final class AppSession` 和 `AppRootView`。
- 依赖：无前置任务。

- [ ] **步骤 1：确认实施前置条件**

运行：

```bash
xcode-select -p
xcodebuild -version
xcodegen --version
```

预期：当前开发者目录指向 `Xcode.app` 内部，Xcode 报告版本 26，XcodeGen 报告版本 2.43 或更高。如果已安装 Xcode 但尚未选中，请在获得用户批准后运行 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`。

- [ ] **步骤 2：创建可生成的项目骨架**

创建 `project.yml`：

```yaml
name: RiverClub
options:
  bundleIdPrefix: com.dafengshuyi
settings:
  base:
    IPHONEOS_DEPLOYMENT_TARGET: 18.0
    SWIFT_VERSION: 6.0
targets:
  RiverClub:
    type: application
    platform: iOS
    sources: [RiverClub]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.dafengshuyi.riverclub
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: true
        INFOPLIST_KEY_UILaunchScreen_Generation: true
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone:
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
  RiverClubTests:
    type: bundle.unit-test
    platform: iOS
    sources: [RiverClubTests]
    dependencies: [{target: RiverClub}]
  RiverClubUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [RiverClubUITests]
    dependencies: [{target: RiverClub}]
```

创建 `RiverClub/App/RiverClubApp.swift`：

```swift
import SwiftUI

@main struct RiverClubApp: App {
    var body: some Scene { WindowGroup { Text("River Club") } }
}
```

运行：

```bash
xcodegen generate
```

预期：成功生成 `RiverClub.xcodeproj`。项目骨架属于配置与生成步骤；业务行为仍须遵循后续的失败测试优先顺序。

- [ ] **步骤 3：编写并运行预期失败的会话测试**

创建 `RiverClubTests/AppSessionTests.swift`：

```swift
import XCTest
@testable import RiverClub

final class AppSessionTests: XCTestCase {
    func testGuestLoginOpensLobbyAndLogoutReturnsToLogin() {
        let session = AppSession()
        XCTAssertEqual(session.route, .login)
        session.continueAsGuest()
        XCTAssertEqual(session.route, .lobby)
        session.logout()
        XCTAssertEqual(session.route, .login)
    }
}
```

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:RiverClubTests/AppSessionTests
```

预期：编译失败，错误明确指出找不到 `AppSession`；失败原因必须是会话功能尚未实现，而不是项目配置或测试语法错误。

- [ ] **步骤 4：实现最小会话功能并让测试通过**

创建 `RiverClub/App/AppSession.swift`：

```swift
import Observation

enum AppRoute: Equatable { case login, lobby, tables, table, tournaments, profile }

@MainActor @Observable
final class AppSession {
    var route: AppRoute = .login
    var chipBalance = 128_500
    func continueAsGuest() { route = .lobby }
    func logout() { route = .login }
    func open(_ route: AppRoute) { self.route = route }
}
```

将 `RiverClub/App/RiverClubApp.swift` 更新为：

```swift
import SwiftUI

@main struct RiverClubApp: App {
    @State private var session = AppSession()
    var body: some Scene { WindowGroup { AppRootView(session: session) } }
}
```

创建 `RiverClub/App/AppRootView.swift`：

```swift
import SwiftUI

struct AppRootView: View {
    @Bindable var session: AppSession
    var body: some View {
        Group {
            switch session.route {
            case .login: Text("River Club Login")
            default: Text("River Club")
            }
        }
        .preferredColorScheme(.dark)
    }
}
```

重新生成项目并运行测试：

运行：

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:RiverClubTests/AppSessionTests
```

预期：`** TEST SUCCEEDED **`。

- [ ] **步骤 5：提交初始搭建内容**

```bash
git add project.yml RiverClub RiverClubTests
git commit -m "feat: bootstrap River Club landscape app"
```

## 任务 2：添加设计系统和共用外壳

**文件：**
- 创建：`RiverClub/DesignSystem/Theme.swift`
- 创建：`RiverClub/DesignSystem/AppSidebar.swift`
- 创建：`RiverClub/DesignSystem/ChipBalancePill.swift`
- 修改：`RiverClub/App/AppRootView.swift`
- 测试：`RiverClubTests/AppSessionTests.swift`

**接口：**
- 依赖：`AppSession.open(_:)`、`AppRoute`。
- 产出：`RCTheme`、`AppSidebar(selection:onSelect:)` 和 `ChipBalancePill(balance:)`。

- [ ] **步骤 1：添加预期失败的侧边栏路由契约测试**

追加到 `AppSessionTests`：

```swift
func testSidebarRoutesAreStable() {
    XCTAssertEqual(AppRoute.sidebarRoutes, [.lobby, .tournaments, .tables, .profile])
}
```

- [ ] **步骤 2：运行聚焦测试**

运行任务 1 中的 `xcodebuild test` 命令，并添加 `-only-testing:RiverClubTests/AppSessionTests/testSidebarRoutesAreStable`。

预期：失败，因为 `AppRoute.sidebarRoutes` 不存在。

- [ ] **步骤 3：实现主题令牌和共用组件**

创建 `Theme.swift`：

```swift
import SwiftUI

enum RCTheme {
    static let background = Color(red: 0.035, green: 0.11, blue: 0.09)
    static let surface = Color(red: 0.06, green: 0.16, blue: 0.13)
    static let surfaceRaised = Color(red: 0.09, green: 0.22, blue: 0.18)
    static let gold = Color(red: 0.84, green: 0.68, blue: 0.34)
    static let primaryText = Color(red: 0.96, green: 0.93, blue: 0.88)
    static let secondaryText = Color(red: 0.60, green: 0.69, blue: 0.65)
    static let corner: CGFloat = 14
}
```

向 `AppRoute` 添加共用导航契约：

```swift
extension AppRoute {
    static let sidebarRoutes: [AppRoute] = [.lobby, .tournaments, .tables, .profile]
}
```

创建 `AppSidebar.swift`，为 `.lobby`、`.tournaments`、`.tables` 和 `.profile` 提供四个带标签的按钮；为每个按钮应用 `.accessibilityIdentifier("sidebar.<route>")`，并调用 `onSelect(route)`。

创建 `ChipBalancePill.swift`：

```swift
import SwiftUI

struct ChipBalancePill: View {
    let balance: Int
    var body: some View {
        Label(balance.formatted(), systemImage: "circle.fill")
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(RCTheme.gold)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RCTheme.surface, in: Capsule())
            .accessibilityLabel("娱乐筹码 (balance)")
    }
}
```

修改 `AppRootView`，使已认证路由渲染一个包含 `AppSidebar` 和当前功能占位视图的 `HStack(spacing: 0)`，而 `.table` 不渲染侧边栏。

- [ ] **步骤 4：运行单元测试**

运行：

```bash
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:RiverClubTests
```

预期：`** TEST SUCCEEDED **`。

- [ ] **步骤 5：提交**

```bash
git add RiverClub/DesignSystem RiverClub/App RiverClubTests
git commit -m "feat: add River Club design system shell"
```

## 任务 3：定义 UI 模型和确定性固定数据

**文件：**
- 创建：`RiverClub/Models/PokerModels.swift`
- 创建：`RiverClub/Services/PokerRepository.swift`
- 创建：`RiverClub/Services/MockPokerRepository.swift`
- 创建：`RiverClubTests/MockPokerRepositoryTests.swift`

**接口：**
- 产出：`PokerTableSummary`、`PokerSeat`、`TournamentSummary`、`ProfileSummary`、`PokerRepository` 和 `MockPokerRepository`。
- 依赖：不依赖视图代码。

- [ ] **步骤 1：编写固定数据契约测试**

创建 `MockPokerRepositoryTests.swift`，验证 `tables()` 至少返回三张牌桌，`featuredTable()` 至少有一个空位，`seats()` 返回正好九个唯一位置且其中正好一个 `isLocalPlayer`，并且任何格式化后的值都不包含 `¥`、`$`、`€` 或 `£`。

- [ ] **步骤 2：运行测试并确认因类型缺失而失败**

运行 `xcodebuild test`，仅执行 `RiverClubTests/MockPokerRepositoryTests`。

预期：失败，因为仓库类型不存在。

- [ ] **步骤 3：实现模型和仓库**

在 `PokerModels.swift` 中定义以下精确签名：

```swift
import Foundation

struct PokerTableSummary: Identifiable, Equatable, Sendable {
    let id: UUID; let name: String; let smallBlind: Int; let bigBlind: Int
    let players: Int; let capacity: Int; let averagePot: Int; let isFavorite: Bool
}
struct PokerSeat: Identifiable, Equatable, Sendable {
    let id: UUID; let position: Int; let initials: String; let name: String
    let chips: Int; let isLocalPlayer: Bool; let status: String?
}
struct TournamentSummary: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case beginner, classic, turbo }
    let id: UUID; let kind: Kind; let name: String; let startTime: Date
    let registered: Int; let capacity: Int; let prizePool: Int; let entryChips: Int
}
struct ProfileSummary: Equatable, Sendable {
    let nickname: String; let level: Int; let handsPlayed: Int
    let voluntaryPutInPot: Double; let tournamentAwards: Int
}
```

使用以下精确签名定义 `PokerRepository`：

```swift
protocol PokerRepository: Sendable {
    func tables() async throws -> [PokerTableSummary]
    func featuredTable() async throws -> PokerTableSummary
    func seats() async throws -> [PokerSeat]
    func tournaments() async throws -> [TournamentSummary]
    func profile() async throws -> ProfileSummary
}
```

使用已批准的名称“翡翠湾”“金色海岸”“午夜俱乐部”和九个确定性座位实现 `MockPokerRepository`。使用固定的 UUID 字面量，以保证 UI 测试稳定。

- [ ] **步骤 4：运行仓库测试**

预期：所有固定数据契约测试通过。

- [ ] **步骤 5：提交**

```bash
git add RiverClub/Models RiverClub/Services RiverClubTests/MockPokerRepositoryTests.swift
git commit -m "feat: add deterministic poker UI fixtures"
```

## 任务 4：实现登录、大厅、牌桌列表和买入流程

**文件：**
- 创建：`RiverClub/Features/Auth/LoginView.swift`
- 创建：`RiverClub/Features/Lobby/LobbyView.swift`
- 创建：`RiverClub/Features/Lobby/TableListView.swift`
- 创建：`RiverClub/Features/Lobby/BuyInSheet.swift`
- 创建：`RiverClubTests/BuyInTests.swift`
- 修改：`RiverClub/App/AppRootView.swift`

**接口：**
- 依赖：`AppSession`、`PokerRepository`、`PokerTableSummary` 和共用设计系统。
- 产出：`BuyInState`、`LoginView`、`LobbyView`、`TableListView` 和 `BuyInSheet`。

- [ ] **步骤 1：编写买入验证测试**

创建 `BuyInTests.swift`：

```swift
import XCTest
@testable import RiverClub

final class BuyInTests: XCTestCase {
    func testBuyInClampsToTableRangeAndBalance() {
        var state = BuyInState(minimum: 2_000, maximum: 10_000, balance: 6_500)
        state.amount = 9_000
        state.normalize()
        XCTAssertEqual(state.amount, 6_500)
        XCTAssertTrue(state.canConfirm)
    }
    func testInsufficientBalanceCannotConfirm() {
        let state = BuyInState(minimum: 2_000, maximum: 10_000, balance: 1_500)
        XCTAssertFalse(state.canConfirm)
    }
}
```

- [ ] **步骤 2：运行测试并确认失败**

预期：失败，因为 `BuyInState` 未定义。

- [ ] **步骤 3：实现流程**

在 `BuyInSheet.swift` 中实现 `BuyInState`，包含 `minimum`、`maximum`、`balance`、可变的 `amount`、`autoTopUp`、`canConfirm`，以及将值限制到 `min(maximum, balance)` 的 `normalize()`。

使用 `NavigationStack`、`safeAreaPadding`、可复用行和以下无障碍标识符，实现四个已批准界面：`login.apple`、`login.guest`、`lobby.quickJoin`、`lobby.allTables`、`tableRow.<uuid>`、`buyIn.slider` 和 `buyIn.confirm`。

将访客登录连接到 `.lobby`，将“查看全部”连接到 `.tables`，将行选择连接到弹出表单，并在确认成功后转到 `.table`。余额不足错误应保留在弹出表单内部显示。

- [ ] **步骤 4：运行单元测试并构建**

运行：

```bash
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:RiverClubTests
xcodebuild build -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

预期：测试通过且构建成功。

- [ ] **步骤 5：提交**

```bash
git add RiverClub/Features/Auth RiverClub/Features/Lobby RiverClub/App RiverClubTests/BuyInTests.swift
git commit -m "feat: implement lobby and buy-in prototype flow"
```

## 任务 5：实现九座扑克桌

**文件：**
- 创建：`RiverClub/Features/Table/PokerSeatView.swift`
- 创建：`RiverClub/Features/Table/BetControlBar.swift`
- 创建：`RiverClub/Features/Table/PokerTableView.swift`
- 创建：`RiverClubTests/PokerTableLayoutTests.swift`
- 修改：`RiverClub/App/AppRootView.swift`

**接口：**
- 依赖：`[PokerSeat]`、`AppSession`、`RCTheme`。
- 产出：`PokerTableLayout.positions(for:)`、`PokerSeatView`、`BetControlBar`、`PokerTableView`。

- [ ] **步骤 1：编写布局不变量测试**

测试 `PokerTableLayout.positions(for: CGSize(width: 956, height: 440))` 返回九个不同的归一化点，本地玩家索引 8 位于牌桌中心下方，所有点均位于 `0...1` 内，并且八名对手的边框均不与本地玩家边框相交。

- [ ] **步骤 2：运行测试并确认失败**

预期：失败，因为 `PokerTableLayout` 未定义。

- [ ] **步骤 3：实现布局和牌桌组件**

使用以下归一化座位中心点：

```swift
static let normalizedCenters: [CGPoint] = [
    .init(x: 0.25, y: 0.16), .init(x: 0.50, y: 0.10), .init(x: 0.75, y: 0.16),
    .init(x: 0.88, y: 0.34), .init(x: 0.86, y: 0.62), .init(x: 0.18, y: 0.68),
    .init(x: 0.12, y: 0.48), .init(x: 0.14, y: 0.27), .init(x: 0.50, y: 0.86)
]
```

在 `PokerSeatView` 中，使用 `.frame(width: 42, height: 42)`、`.clipShape(Circle())` 和 `.fixedSize()` 渲染头像，确保头像永不压缩。对较长昵称使用 `ViewThatFits`。

在 `PokerTableView` 中，将公共牌置于中心，奖池放在公共牌下方，筹码放在奖池下方。将弃牌/跟注/加注控件放在右下方安全区域内边距中，并将聊天控件放在左下方。添加从 `table.seat.0` 到 `table.seat.8`、`table.pot`、`action.fold`、`action.call` 和 `action.raise` 的标识符。

- [ ] **步骤 4：运行布局测试并构建**

预期：九座布局不变量测试通过，且应用可针对 iPhone 16 Pro Max 成功构建。

- [ ] **步骤 5：提交**

```bash
git add RiverClub/Features/Table RiverClub/App RiverClubTests/PokerTableLayoutTests.swift
git commit -m "feat: add accessible nine-seat poker table UI"
```

## 任务 6：实现锦标赛和个人资料

**文件：**
- 创建：`RiverClub/Features/Tournaments/TournamentsView.swift`
- 创建：`RiverClub/Features/Profile/ProfileView.swift`
- 修改：`RiverClub/App/AppRootView.swift`
- 修改：`RiverClubTests/MockPokerRepositoryTests.swift`

**接口：**
- 依赖：`TournamentSummary`、`ProfileSummary`、`PokerRepository`。
- 产出：`TournamentTab.filtered(_:)`、已批准的锦标赛卡片，以及个人资料摘要/设置链接。

- [ ] **步骤 1：编写锦标赛筛选测试**

创建测试，断言 `.upcoming.filtered(fixtures)` 排除已过去的开始时间，`.registered` 仅包含提供给筛选器的已报名标识符，并且固定个人资料数据中的 VPIP 位于 `0...1` 内。

- [ ] **步骤 2：运行聚焦的仓库测试**

预期：失败，因为 `TournamentTab.filtered(_:)` 不存在。

- [ ] **步骤 3：实现两个界面**

将 `TournamentTab` 定义为 `upcoming`、`registered`、`active` 和 `finished`，并提供 `filtered(_:now:registeredIDs:) -> [TournamentSummary]`。构建对应的标签页；每张卡片显示开始时间、报名人数、奖励筹码以及免费/报名状态。构建个人身份信息、等级进度、三项已批准的统计数据，以及牌局历史、成就、账户与安全、声音与触感反馈的链接。

添加标识符 `tournaments.tab.<state>`、`tournament.<uuid>`、`profile.nickname` 和 `profile.settings`。

- [ ] **步骤 4：运行测试并构建**

预期：单元测试通过，且所有根路由均可编译。

- [ ] **步骤 5：提交**

```bash
git add RiverClub/Features/Tournaments RiverClub/Features/Profile RiverClub/App RiverClubTests
git commit -m "feat: add tournament and profile screens"
```

## 任务 7：添加加载中、离线、空数据和失败状态

**文件：**
- 创建：`RiverClub/Features/Shared/LoadableContent.swift`
- 修改：`RiverClub/Features/Lobby/LobbyView.swift`
- 修改：`RiverClub/Features/Lobby/TableListView.swift`
- 修改：`RiverClub/Features/Tournaments/TournamentsView.swift`
- 创建：`RiverClubTests/LoadableStateTests.swift`

**接口：**
- 产出：`enum LoadableState<Value>` 和 `LoadableContent`。
- 依赖：功能内容视图和仓库错误。

- [ ] **步骤 1：编写状态映射测试**

测试加载中、已加载空数据、已加载有内容、离线和失败状态的确定性映射。验证离线/失败时提供重试，仅对筛选后的空结果提供清除筛选，并且侧边栏状态保持不变。

- [ ] **步骤 2：运行测试并确认失败**

预期：失败，因为 `LoadableState` 不存在。

- [ ] **步骤 3：实现明确的状态视图**

定义：

```swift
enum LoadableState<Value> {
    case loading
    case loaded(Value)
    case offline(cached: Value?)
    case failed(message: String)
}
```

为加载状态实现骨架行，为筛选后的空列表实现清除筛选操作，在存在缓存数据时显示非模态离线横幅，并为无缓存的失败状态提供行内重试操作。绝不能使用临时 Toast 替换整个根视图。

- [ ] **步骤 4：运行状态测试和完整单元测试套件**

预期：所有单元测试通过。

- [ ] **步骤 5：提交**

```bash
git add RiverClub/Features RiverClubTests/LoadableStateTests.swift
git commit -m "feat: add resilient UI loading and error states"
```

## 任务 8：添加端到端 UI 验证

**文件：**
- 创建：`RiverClubUITests/CoreFlowUITests.swift`
- 创建：`RiverClubUITests/LandscapeLayoutUITests.swift`

**接口：**
- 依赖：任务 2–7 中的无障碍标识符。
- 产出：针对已批准 UI 流程和布局不变量的自动化验收证据。

- [ ] **步骤 1：编写核心流程 UI 测试**

使用 `-uiTesting` 启动应用，点击 `login.guest`，验证大厅，打开全部牌桌，选择第一行，设置买入金额并确认，然后断言 `table.seat.0...8`、`table.pot` 和全部三个操作按钮均存在。

- [ ] **步骤 2：编写横屏和合规性 UI 测试**

断言窗口宽度大于高度，全部九个座位边框均可点击或可见且不与本地玩家边框相交，本地头像的宽高差不超过一个点，并且应用静态文本不包含 `¥`、`$`、`€` 或 `£` 中的任何一个。

- [ ] **步骤 3：在 iPhone 16 Pro Max 上运行 UI 测试**

运行：

```bash
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:RiverClubUITests
```

预期：显示 `** TEST SUCCEEDED **`，且完整流程在横屏模式下完成。

- [ ] **步骤 4：运行完整验证套件**

运行：

```bash
xcodebuild clean test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

预期：干净构建成功，且所有单元测试/UI 测试均通过。

- [ ] **步骤 5：提交验证内容**

```bash
git add RiverClubUITests
git commit -m "test: verify River Club core landscape flow"
```

## UI 原型获批后的后续计划

以下独立子系统需要单独制定规格和实施计划：

1. 德州扑克规则引擎：牌组、发牌、下注轮次、合法操作、边池、摊牌、牌型评估、确定性模拟和属性测试。
2. 实时多人游戏平台：牌桌匹配、权威游戏服务器、断线重连、操作计时器、反作弊边界、可观测性和负载测试。
3. 账户与娱乐筹码服务：Sign in with Apple 服务端验证、个人资料、筹码账本、每日发放、幂等性、内容治理、隐私和账户删除。
4. 客户端/服务端集成与发布：API 契约、WebSocket 协议、本地化、分析同意、App Store 元数据、TestFlight 和生产环境发布。
