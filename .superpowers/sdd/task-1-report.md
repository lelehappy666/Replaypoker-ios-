# 任务 1：机器人身份目录与头像资源报告

## 状态

已完成。实现仅覆盖任务 1：展示层机器人身份目录、真人头像资源、许可证记录、头像组件与对应测试；未修改机器人决策或扑克规则。

## 实现

- 新增 `RobotIdentity`（可编码、可比较、可识别、可并发传递）和 `RobotIdentityCatalog.all`。
- 固定建立 24 组唯一中文名称、稳定标识、头像资源名、Pexels 原页面、摄影师和无障碍描述绑定。
- `draw(count:using:)` 使用可注入随机源；相同种子返回相同且不重复的身份。
- `preview(for:count:)` 对桌标识采用稳定 FNV-1a 种子，保证同一桌标识的大厅预览稳定且不重复。
- 新增 `RobotAvatarView`：优先圆形真人头像，加载失败时显示姓名前两个字，占位样式带细金边。
- 新增 `Assets.xcassets` 中 24 张真人头像（每张 512×512），以及 `RobotAvatarLicenses.json`。
- 每条许可证记录包含资源名、Pexels 页面、摄影师、`Pexels License`、许可页和 512×512 尺寸说明。页面素材均从检索结果明确标为成人／中年／年长真人肖像的 Pexels 页面选取，未使用卡通、名人、品牌人物或未成年人。
- 手工 Xcode 工程已登记两份 Swift 源、测试、资产目录和许可证资源；原工程设置要求 `AppIcon`，故在资源目录中补入空的 `AppIcon` 声明以使资产编译通过，未改变既有应用图标内容。

## 变更文件

- `RiverClub/Models/RobotIdentity.swift`
- `RiverClub/DesignSystem/RobotAvatarView.swift`
- `RiverClub/Resources/Assets.xcassets/`（24 组头像资源及 AppIcon 声明）
- `RiverClub/Resources/RobotAvatarLicenses.json`
- `RiverClubTests/RobotIdentityTests.swift`
- `RiverClub.xcodeproj/project.pbxproj`（本项目按 `.gitignore` 忽略，但当前共享工作区已完成手工注册）

## TDD 记录

### RED

先新增 `RobotIdentityTests.swift` 并注册到测试目标，再运行：

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' -only-testing:RiverClubTests/RobotIdentityTests
```

原始关键失败信息：

```text
RobotIdentityTests.swift:7:22: error: cannot find 'RobotIdentityCatalog' in scope
Testing failed: Cannot find 'RobotIdentityCatalog' in scope
** TEST FAILED **
```

失败原因符合预期：生产目录类型尚不存在。

### GREEN

实现目录、资源和头像组件后重跑相同聚焦测试。Xcode 结果包摘要：

```text
result: Passed
totalTestCount: 3
passedTests: 3
failedTests: 0
```

## 验证结果

- `RobotIdentityTests`：3 通过、0 失败。
- `RiverClubTests` 全量：132 通过、0 失败、0 跳过。
- 资源自查：许可证清单 24 条；资源名 24 个且互异；Pexels 原页面 24 个且互异；摄影师字段 24 条均非空；24 张图片的宽、高均为 512。
- Xcode 构建日志确认 `Assets.xcassets` 由 `actool` 成功编译为 `Assets.car`。
- 已运行 `git diff --check`，无空白错误。

## 风险与自查

- Pexels 页面和许可状态属于外部服务，后续发布前应再做一次链接可访问性与许可条款复核；当前所有记录保留了可核验的原始页面、摄影师和 Pexels License。
- `RiverClub.xcodeproj/` 受项目现有 `.gitignore` 忽略，故其手工注册状态在当前共享工作区有效但不会随本次普通 Git 提交入库；`project.yml` 的 `sources: [RiverClub]` 会在重新生成工程时纳入这些新增源和资源。

## 审查修复（许可证逐项记录与边界行为）

### 修复内容

- `RobotAvatarLicenses.json` 的 24 个 `assets` 条目均新增了显式的 `"license": "Pexels License"`；根级许可说明保留。
- 新增自动化测试，直接从已编译应用资源包读取许可证清单，验证：清单条目数为 24、每条许可均为 `Pexels License`、资产名集合与 `RobotIdentityCatalog.all` 的头像资源名集合完全相同。
- 新增 `draw(count:using:)` 与 `preview(for:count:)` 的 `0`、负数与大于 24 边界测试：前两者返回空数组，后者最多返回 24 个不重复身份。

### 本次 TDD 记录

先新增上述测试，未改动许可证清单即运行聚焦测试。Xcode 结果包的原始关键失败信息：

```text
result: Failed
totalTestCount: 6
passedTests: 5
failedTests: 1
RobotIdentityTests/testLicenseManifestContainsOnePexelsLicenseForEveryCatalogIdentity()
XCTAssertEqual failed: ("0") is not equal to ("24")
```

该失败符合预期，证明测试读取的是应用已打包的 JSON，且逐项许可字段确实尚未存在。补齐 24 条许可证字段后，使用相同 Xcode 命令重跑：

```text
result: Passed
totalTestCount: 6
passedTests: 6
failedTests: 0
```

本次聚焦测试重新构建并运行应用测试目标，资源清单已由应用资源包成功提供给测试；未改动牌局生产逻辑，因此按要求未重复执行 132 项全量测试。
