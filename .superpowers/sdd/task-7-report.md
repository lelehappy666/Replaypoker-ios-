# 任务 7 验收报告：核心 UI 闭环、边界加固与中文文档

## 结论

任务 7 已完成。新增 UI 测试通过真实游客登录、选桌、买入和弃牌流程生成完成记录，重启后复用同一固定测试 store，验证记录列表、九座位、最终底牌、全应用删除确认、空态与余额不变；没有直接插入或伪造完成记录。

## RED / GREEN

### RED

- 先新增 `HandHistoryFlowUITests.testCompletedHandAppearsWithFoldedCardsAndCanBeDeleted()`，并为既有 `CoreFlowUITests` 增加 `-resetHistoryStore`。
- 首次端到端运行确实完成买入、真人 `fold` 并等待到 `action.nextHand`；终止并以 `-openHistory` 重启后，在 `history.balance` 处失败。
- 统计：1 项测试，1 失败，退出码 65。失败原因是旧实现每次 `uiTestingImmediate()` 都删除固定临时目录，且未处理 `-openHistory` 初始路由，直接对应缺失功能。
- 首次 SwiftPM 定向运行曾因系统 `sandbox-exec: sandbox_apply: Operation not permitted` 失败；这是环境权限错误，获准在系统环境重跑后正常，不作为 RED。

### GREEN

- `AppSession.uiTestingImmediate(resetHistoryStore:)` 始终使用固定目录 `RiverClub-Immediate-UITests`；仅 `-resetHistoryStore` 会在目录存在时删除，删除错误不再被吞掉。
- `-openHistory` 不删除目录；创建 `AppSession` 后依次调用 `continueAsGuest()` 与 `open(.tables)`。
- 两个参数只控制 UI 测试目录和初始路由，没有写入记录、余额或身份数据。
- 首次修正后测试已能看到 `history.balance` 和真实记录 `history.row.ui-hand-1`。无障碍层级确认 `history.detail` 的实际类型为 `ScrollView`，测试按当前实现查询；九座位与底牌保持 `.other`。
- 删除后的空态标识原先分散到 Image/StaticText；为普通空态与筛选空态增加 `.accessibilityElement(children: .contain)` 后，`history.empty` 成为稳定语义容器。
- 最终定向及组合运行均通过，0 失败。

### 正式评审修复 RED / GREEN

- UI RED：将自动化证据收紧为固定真人座位 8。新增 `history.holeCard.8.0` 与 `.8.1` 后两个断言均已通过；新增 `history.seat.8` 标签包含“已弃牌”的断言在旧实现上失败，1 项测试、1 失败，退出码 65。
- UI GREEN：仅为座位结果容器补充由昵称、状态和筹码变化组成的公开可访问性标签；重跑后 seat 8 的两张牌与“已弃牌”语义同时通过。
- 边界 RED：新增错误诊断夹具，其中源码回显含 `botSettings`，但主错误是其他成员 `otherMember` 不存在。在精确 matcher 尚未实现时，定向测试因 `completedHistoryDiagnostics` 不存在而明确编译失败。
- 边界 GREEN：matcher 现在只接受 `has no member '<目标>'` 或 `'<目标>' is inaccessible due to`；夹具证明旧宽松组合被拒绝，两种真实主诊断形式被接受。
- 六个探针分别先 typecheck 安全祖先路径：`record.communityCards`、`archiveMetadata.tableDisplayName` 或 `store.accountBalance`；源码也显式声明 `StoredHandRecord` 与 `LocalPokerStore` 类型控制，证明失败确实落在末级目标成员。

## 实际模拟器

- 型号：iPhone 17 Pro Max
- 系统：iOS 26.5
- UDID：`86B6F41B-B5EA-4267-8FA3-0C92481DE8E8`
- 简报中的固定 UDID 仍有效，但本机 `simctl` 将其报告为 iPhone 17 Pro Max，而不是 iPhone 16 Pro Max，因此按实际输出记录。

## 端到端真实证据

组合 UI 测试执行了以下真实路径：

1. `login.guest` 游客登录。
2. `lobby.allTables` 进入全部牌桌，选择固定真实牌桌行。
3. 调整 `buyIn.slider` 到 0.25 后点击 `buyIn.confirm`，由真实账本完成买入。
4. 等待真人行动并点击 `action.fold`，由机器人和规则引擎继续推进，等待真实结算保存后的 `action.nextHand`。
5. 终止应用，以 `-openHistory` 重启；读取同一固定 store，显示 `history.row.ui-hand-1`。
6. 打开详情并验证 9 个 `history.seat.*`，且 `history.holeCard.*` 总数大于 2。更关键的自动化证据是：测试明确要求固定真人座位 8 的 `history.holeCard.8.0` 和 `.8.1` 存在，并要求 `history.seat.8` 的公开可访问性标签包含“已弃牌”。因此现在由自动化直接证明“刚执行 fold 的真人座位在完成存档中仍显示两张最终底牌”，不再依赖失败诊断层级推断 18 张牌。
7. 记录删除前 `history.balance` 为“娱乐筹码 117,100”；点击 `history.deleteOne` 和全应用覆盖层中的 `history.confirmDeleteOne` 后出现 `history.empty`，余额标签保持相同。
8. `CoreFlowUITests` 继续点击 `action.nextHand` 并验证手牌 ID 更新以及下一手可再次行动，证明既有闭环无回归。

## 隐藏信息边界探针

新增普通 `import PokerCore` + `import PokerSession` 的临时源码 typecheck：

- 控制源码必须先以状态 0 编译成功。
- 六个探针逐项验证 `record.deck`、`record.seed`、`record.checkpoint`、`archiveMetadata.botSettings`、`archiveMetadata.decisionModel` 和 `store.pendingShowdownObservation`。
- 每个探针都要求状态 1，且主诊断必须精确绑定目标成员：`has no member '<目标>'` 或 `'<目标>' is inaccessible due to`；同时明确拒绝 `no such module`。
- 每个末级探针前的分层安全控制源必须先以状态 0 编译成功。
- PokerCoordinator 既有控制源码也补充拒绝 `no such module` 的断言。

## README

中文 README 已删除“仅 UI 原型、没有规则引擎、固定牌桌数据完成牌局”等过时范围，准确说明：

- 本地 `PokerCore` 规则引擎与普通桌可玩闭环已经接入。
- 机器人只依据自身安全观察和公开桌面信息决策。
- 已完成牌局永久保存在 Application Support，可在“我的牌局”查看最终结果和所有实际获发的最终底牌。
- 进行中牌局仍隐藏对手底牌，弃牌者牌面只在完成存档详情显示。
- 娱乐筹码无现金价值；仍无实时多人网络、真钱充值提现、云同步和生产身份服务。

## 最终验证统计

自审加固后重新执行步骤 3–5，结果如下：

- PokerSession + PokerCoordinator 公开 API 定向：6 项测试，0 失败，耗时 2.990 秒。
- HandHistory UI 定向：1 项测试，0 失败，测试耗时 34.588 秒。
- PokerCore 全量：358 项测试，0 失败，耗时 172.819 秒。
- RiverClubTests：94 项测试，0 失败，耗时 1.589 秒。
- CoreFlow + HandHistory UI：2 项测试，0 失败，耗时 65.490 秒。
- `xcodegen generate`：成功，新 UI 测试已进入 RiverClubUITests Sources。
- generic iOS `build-for-testing`：`TEST BUILD SUCCEEDED`。
- `git diff --check`：通过，无空白错误。

## 独立复审

- 旧存档兼容：既有“旧记录缺少显示元数据仍能解码且不会被改写”等全量测试通过；本任务未改变存档模型或迁移逻辑。
- 新元数据幂等和安全文本：既有结算元数据幂等、冲突拒绝与九座位显示测试通过；本任务未增加隐藏元数据字段。
- 弃牌底牌边界：进行中安全观察边界测试通过；真实完成存档详情显示弃牌真人最终底牌。
- 日期/牌桌筛选：既有组合筛选稳定倒序、自然日范围及应用筛选测试通过。
- 删除隔离：包测试、应用单元测试和 UI 测试共同证明单局/全部删除不修改经济、统计、永久身份与当前会话。
- 路由：`open(.tables)` 只打开“我的牌局”，全部牌桌仍使用 `.tableBrowser`；相关应用测试通过。
- 横屏布局：九座位、详情网格、筛选区、大字号确认弹窗布局测试通过；核心 UI 在 956×440 模拟器画布完成交互，无自动化可见遮挡失败。
- CoreFlow：真实买入到下一手组合 UI 测试通过。
- 自审修复：将测试目录删除从忽略错误改为存在时必须成功删除，避免旧测试数据静默残留；修复后完整重跑全部要求验证。

## 保留验收与顾虑

- iPhone 16 Pro Max 真机视觉验收无法由 iPhone 17 Pro Max / iOS 26.5 模拟器自动替代，仍明确保留，需人工检查牌面、头像、筛选区和确认弹窗在真机横屏安全区内无视觉遮挡。
- Xcode 日志存在 `IDERunDestination: Supported platforms ... is empty`、LLDB 版本快照和模拟器 Accessibility bundle 重复类警告；所有要求测试和构建仍以退出码 0 完成。这些是工具链警告，不是测试失败。
- `project.yml` 已用目录级 `sources: [RiverClubUITests]` 自动纳入新增测试，重新生成工程后已确认 PBX Sources 包含 `HandHistoryFlowUITests.swift`，无需增加重复的单文件配置。
