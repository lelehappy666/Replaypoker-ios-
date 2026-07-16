# 任务 6 实施报告：二次确认删除与原子错误恢复

## 结论

已完成单局删除和全部删除的显式待确认状态、二次确认弹窗、失败保留与同操作重试。请求动作不写入存储；确认成功后清理待确认、详情选择和删除错误，并在保留当前筛选条件的前提下重载列表；确认失败时保留待确认操作、列表、详情选择和中文错误，并向调用方重新抛出原始错误。

未实现任务 7 的 UI E2E，也未加入测试专用伪记录注入。

## TDD 证据

### RED

先在 `HandHistorySessionTests.swift` 和 `HandHistoryLayoutTests.swift` 添加取消、成功、失败、经济状态、当前会话、确认文案与标识测试，再运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
  -only-testing:RiverClubTests/HandHistorySessionTests \
  -only-testing:RiverClubTests/HandHistoryLayoutTests CODE_SIGNING_ALLOWED=NO
```

结果为预期 RED：编译失败，明确报告 `AppSession` 缺少 `requestDeleteHand`、`requestDeleteAllHistory`、`cancelHistoryDeletion`、`confirmHistoryDeletion`，且 `HandHistoryViewState` 缺少 `pendingDeletion`、`deletionError`。退出码 65。

### GREEN

完成最小实现后重新运行同一命令，结果：

- `HandHistoryLayoutTests`：5 个测试通过。
- `HandHistorySessionTests`：7 个测试通过。
- 合计：12 个测试通过，0 失败。
- `xcodebuild`：`** TEST SUCCEEDED **`，退出码 0。

## 回归与构建

### RiverClub 全量单元回归

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'platform=iOS Simulator,id=86B6F41B-B5EA-4267-8FA3-0C92481DE8E8' \
  -only-testing:RiverClubTests CODE_SIGNING_ALLOWED=NO
```

结果：88 个测试通过，0 失败，`** TEST SUCCEEDED **`。

### PokerSession 删除不变量

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --package-path Packages/PokerCore \
  --filter deletingHistoryIsAtomicAndPreservesLedgerSessionStatisticsAndReceipts

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --package-path Packages/PokerCore \
  --filter deletedHistoryKeepsHandAndSettlementIdentitiesPermanentlyReserved
```

结果：两个目标测试分别 1/1 通过。证明确认删除只移除存档记录，余额、账本、活动会话、统计、命令回执均保持不变，已删除牌局 ID 和结算业务 ID 仍被永久保留。

### Generic build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build -project RiverClub.xcodeproj -scheme RiverClub \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

结果：`** BUILD SUCCEEDED **`，退出码 0。

## 不变量证据

- 单局请求后存储仍为三条记录；取消后仍为三条记录，并清除待确认和错误。
- 单局确认成功后仅删除目标记录，余额与统计保持不变；当前筛选保持不变；待确认、详情选择和错误均被清除。
- 删除依赖失败时，存储记录、展示列表和详情选择保持原值；待确认仍为相同 `HandID`；中文错误为“牌局存档删除失败，请重试。”；再次确认仍执行同一操作并重新抛错。
- 全部删除请求阶段不写存储；确认后存档列表为空，活动现金桌会话、余额与统计保持原值。
- PokerSession 既有原子性测试进一步覆盖账本和命令回执；永久身份测试覆盖牌局 ID 与结算业务 ID 不可复用。

## UI 与可访问性

- 单局确认文案包含“牌桌名 · 日期 · 第 N 手”。
- 全部删除确认文案明确“余额、统计和账本不会删除”。
- 两个确认按钮均使用 `role: .destructive`。
- 标识：`history.confirmDeleteOne`、`history.confirmDeleteAll`、`history.cancelDelete`。
- 普通详情删除按钮和全部清空按钮只发起请求，不直接写入存储。
- 确认失败时中文错误附加在仍由 pending 状态驱动的确认弹窗中，可直接重试。

## 变更文件

- `RiverClub/Features/History/HandHistoryView.swift`
- `RiverClub/Features/History/HandHistoryDetailView.swift`
- `RiverClub/Features/History/HandHistoryViewState.swift`
- `RiverClub/App/AppSession.swift`
- `RiverClubTests/HandHistorySessionTests.swift`
- `RiverClubTests/HandHistoryLayoutTests.swift`
- `.superpowers/sdd/task-6-report.md`

## 自审

- 逐项对照任务简报，确认 request、cancel、confirm 成功和 confirm 失败四条状态路径均有测试。
- 检查删除入口，未发现绕过确认直接调用存储删除的普通卡片路径。
- 检查失败分支，未调用 `loadHandHistory()`，因此不会覆盖原列表或详情选择；错误重新抛出。
- 检查成功分支，先清待确认、详情选择和错误，再使用原筛选重载。
- 检查存储范围，应用层只消费任务 4 已注入的删除闭包，没有修改经济、会话或身份数据。
- `git diff --check` 无空白错误。

## 顾虑

无已知功能阻塞。按任务边界未执行任务 7 的 UI E2E；弹窗交互由状态机单元测试、确认展示契约测试和 SwiftUI generic build 覆盖。

---

## 正式评审修复：根层确认弹层

### 问题与根因

正式评审指出两个系统 `alert` 的 `isPresented` 绑定忽略 setter。原实现以 pending 推导 `true`，但丢弃 SwiftUI 写回的 `false`：确认失败后 pending 不变，无法可靠产生下一次系统弹窗所需的重现跃迁；系统关闭也无法明确取消。此外，单局弹窗挂在详情视图上，详情 selection 消失时可能留下不可见 pending。

根因是把业务 pending 状态和系统 alert 的双向呈现生命周期拼接在一起，却没有定义 `false` 写回语义。

### 修复 RED

先补充以下测试：

- 删除失败且保持同一 pending 时，纯展示策略仍返回同一弹层和确认动作标识，并展示中文错误。
- 显式取消后清除 pending，纯展示策略不再返回弹层。
- selection 消失但列表项仍存在时，单局弹层继续可见，文案仍为“牌桌名 · 日期 · 第 N 手”。
- 删除失败后二次确认的依赖调用计数为两次，且两次均为同一 `HandID`。

随后运行目标测试命令，结果为预期 RED：编译失败，明确报告 `HandHistoryDeletionPresentation` 缺少 `overlay(for:)`，退出码 65。

### 最小修复

- 删除两个系统 `alert` 及忽略 setter 的 `Binding<Bool>`。
- 新增可比较、可发送的 `HandHistoryDeletionOverlay` 纯展示模型，携带原 pending、标题、文案、确认标题和确认标识。
- `HandHistoryDeletionPresentation.overlay(for:)` 直接由 `HandHistoryViewState` 派生：
  - pending 不存在时不呈现；
  - 单局 pending 优先使用详情快照，selection 消失时回退到已加载列表项；
  - 全部 pending 使用固定不变量文案；
  - 删除错误只追加到同一展示模型，不改变 pending 和确认动作。
- 在根 `HandHistoryView` 使用条件 `ZStack` overlay 统一承载单局与全部确认。
- 弹层出现时，底层内容同时使用 `allowsHitTesting(false)` 和 `accessibilityHidden(true)`，遮罩覆盖整个历史视图，背景无法交互。
- 取消按钮明确调用 `cancelHistoryDeletion()`；确认按钮继续使用 `role: .destructive`，并调用 `confirmHistoryDeletion()`。
- 确认失败不清 pending，因此根层 overlay 持续存在并展示错误；同一确认按钮可直接再次调用相同删除依赖，不依赖系统 false→true 重现。

### 修复 GREEN 与最终验证

- 目标 `HandHistorySessionTests` + `HandHistoryLayoutTests`：15 个测试通过，0 失败，`** TEST SUCCEEDED **`。
- 全量 `RiverClubTests`：91 个测试通过，0 失败，`** TEST SUCCEEDED **`。
- `deletingHistoryIsAtomicAndPreservesLedgerSessionStatisticsAndReceipts`：1/1 通过。
- `deletedHistoryKeepsHandAndSettlementIdentitiesPermanentlyReserved`：1/1 通过。
- generic iOS Simulator build：`** BUILD SUCCEEDED **`。
- `git diff --check`：无空白错误。

### 修复自审

- `RiverClub/Features/History` 中已不存在系统 `.alert(`、`Binding<Bool>` 或忽略 setter 的实现。
- 单局和全部确认均由根层同一个 pending 派生路径承载。
- 单局 selection 消失边界有列表项回退测试，不会留下不可见 pending。
- 删除失败二次确认计数明确为同一 `HandID` 两次，证明重试命中相同依赖。
- `history.confirmDeleteOne`、`history.confirmDeleteAll`、`history.cancelDelete` 保持不变；两个确认按钮保持 destructive role。
- 未新增任务 7 UI E2E，也未注入测试专用伪记录。

### 修复新增变更文件

- `RiverClubTests/Support/HandHistoryAppTestSupport.swift`：仅增加删除尝试观察闭包，用于验证同一 `HandID` 重试计数；真实存档夹具生成路径未改变。

### 修复后顾虑

无已知功能阻塞。任务 7 UI E2E 仍按边界未执行；根层展示与状态行为由纯策略测试、会话测试和编译回归覆盖。

---

## 第二轮正式评审修复：全应用模态与自适应布局

### 问题与根因

第二轮评审确认上一版自定义确认层只覆盖 `HandHistoryView` 的右侧内容区。应用侧栏仍可点击且仍暴露给辅助功能，用户可在删除 pending 存在时离开历史页面；返回后若载入失败或目标项已不在 selection/list 中，展示策略会返回 `nil`，形成不可见且无法处理的 pending。此外，固定高度与横向按钮在 424 点高度、辅助功能字号下存在内容或操作被裁切的风险，也没有显式的模态语义与辅助功能 Escape 取消契约。

### 第二轮 RED

先新增以下失败测试：

- 历史删除模态必须禁用并从辅助功能树隐藏整个应用 shell，而非仅历史内容区。
- pending 对应牌局同时不在 selection 和列表项中时，仍必须返回可见确认层。
- 424 点高度配合辅助功能字号时，确认层必须使用纵向滚动并将操作按钮纵向排列。
- 确认展示模型必须声明 Escape 对应取消操作。

目标测试首次编译按预期失败，明确报告缺少 `AppRootModalPolicy`，退出码 65。

### 第二轮最小修复

- 将删除确认层上移至 `AppRootView` 最外层，覆盖侧栏、导航内容、买入弹层和牌桌恢复提示。
- 新增纯策略 `AppRootModalPolicy`；确认层出现时，对整个应用 shell 同时应用 `allowsHitTesting(false)` 与 `accessibilityHidden(true)`。
- `HandHistoryDeletionPresentation` 在目标牌局快照和列表项都缺失时改用稳定的通用中文说明，确保 pending 始终有可处理的确认层。
- 为展示模型新增 Escape 取消契约；实际视图添加模态辅助功能特征和 `.accessibilityAction(.escape)`，统一调用取消逻辑。
- 新增纯布局策略 `HandHistoryDeletionLayout`：在可用高度不足时启用纵向滚动，辅助功能字号下将操作按钮纵向排列；SwiftUI 确认层使用该策略渲染。
- 保持确认按钮 destructive role 和既有自动化标识不变；失败后仍保留 pending、错误和同操作重试。

### 第二轮 GREEN 与最终验证

- 目标 `AppSessionTests` + `HandHistoryLayoutTests` + `HandHistorySessionTests`：24 个测试通过，0 失败，`** TEST SUCCEEDED **`。
- 全量 `RiverClubTests`：94 个测试通过，0 失败，`** TEST SUCCEEDED **`（iPhone 17 Pro，iOS 26.5）。
- `deletingHistoryIsAtomicAndPreservesLedgerSessionStatisticsAndReceipts`：1/1 通过。
- `deletedHistoryKeepsHandAndSettlementIdentitiesPermanentlyReserved`：1/1 通过。
- generic iOS Simulator build：`** BUILD SUCCEEDED **`。

首次执行完整测试时指定的 iPhone 16 Pro 不存在，因此命令在测试执行前以目的地错误退出；随后改用本机可用的 iPhone 17 Pro 完成上述 94/94 回归。首次核心包命令使用系统默认 Swift 工具链，因缺少 `Testing` 模块在编译阶段退出；固定 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 后，两个目标不变量用例均通过。

### 第二轮自审

- 删除确认层只在 `AppRootView` 渲染，历史页面不再承载局部遮罩。
- 全应用 shell 的交互与辅助功能可见性由同一纯策略控制，并有单元测试覆盖。
- selection、列表项和加载状态同时缺失时仍能显示通用确认文案，Escape 与取消按钮都清除 pending。
- 424 点高度和辅助功能字号布局由纯策略测试覆盖，实际视图消费同一策略。
- 未修改 PokerSession 删除实现及经济数据路径；两条既有删除不变量继续通过。
