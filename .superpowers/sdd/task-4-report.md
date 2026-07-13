# 任务 4 实现报告

## 状态

已实现登录、大厅、牌桌列表和买入原型流程，并接通：

`游客登录 → 游戏大厅 → 查看全部/选择牌桌 → 买入确认 → 牌桌占位页`

## TDD 记录

1. 先创建 `RiverClubTests/BuyInTests.swift`，未添加生产实现。
2. 使用最小 `swiftc` 类型检查取得 RED，明确报错：`cannot find 'BuyInState' in scope`。
3. 在 `BuyInSheet.swift` 中最小实现 `BuyInState`，随后测试源码 iOS 类型检查通过。

受本机 CoreSimulator 版本不匹配影响，没有执行 XCTest，未声称测试运行通过。

## 实现内容

- 新增中文登录界面及 `login.apple`、`login.guest` 标识符。
- 新增大厅加载/离线重试状态、推荐桌、热门桌、快速加入和查看全部入口。
- 新增牌桌列表、盲注/收藏筛选、加载/空数据/离线重试状态及复用 `TableRow`。
- 新增买入状态、金额限制、自动补充开关、余额不足弹窗内提示与确认路由。
- 新增所有任务要求的 accessibility identifiers。
- 将新增源文件和 `BuyInTests.swift` 加入 Xcode 工程对应 target。
- 未实现扑克引擎、网络、真钱、锦标赛或个人中心等任务外功能。

## 验证

- RED：最小 `swiftc` 类型检查确认 `BuyInState` 缺失。
- GREEN：完整 App 源码（含 Observation 宏和 AppRoot 路由）面向 `arm64-apple-ios18.0` 的 `swiftc -typecheck`，退出码 0。
- GREEN：`BuyInTests.swift` 使用 iPhoneOS XCTest overlay/framework 类型检查，退出码 0。
- Xcode 工程：`plutil -lint RiverClub.xcodeproj/project.pbxproj` 通过；`xcodebuild -list` 正确识别三个 target 和 RiverClub scheme。
- `git diff --check` 通过。

## 环境限制与顾虑

- CoreSimulator 1051.50.0 低于 Xcode 要求的 1051.55.0，无法运行指定模拟器 XCTest。
- 沙箱内 `xcodebuild build-for-testing` 还会阻止 Observation 宏插件；沙箱外 Xcode 报 iOS 26.5 平台不可用。因此采用沙箱外全量 `swiftc` iOS 类型检查作为当前可行构建验证。
- Apple 登录按钮在此原型中仅进入访客式本地流程；未接入 Apple 身份验证或网络服务，符合本任务不实现网络认证的范围。
