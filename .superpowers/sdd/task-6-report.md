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
