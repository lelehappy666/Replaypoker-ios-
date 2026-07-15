# 任务 6 实施报告

## 实施结果

- 新增 `CashTableAnimationMapper`，按领域事件原顺序生成发牌、盲注、行动、筹码移动、换街、公共牌、退回、底池分配和赢家高亮动画。
- 真人两张底牌仅按两次发牌事件依次明牌；数量或牌面状态异常时拒绝。机器人发牌事件始终只包含牌背。
- 动画播放器逐项更新 `state.animation` 并通过注入的 `sleep` 串行让出，保留暂停和状态版本门禁。
- 新增安全摊牌、结算保存、失败中文状态、同一业务编号重试及下一手门禁；下一手会重新冻结传入的机器人设置。
- 摊牌仅读取 `pendingShowdownObservation`：未弃牌且有排名的座位明牌，已弃牌或不安全座位保持两张牌背。

## TDD 证据

- 动画 RED：新测试首次因缺少 `CashTableAnimationMapper` 编译失败。
- 结算 RED：新测试首次因缺少 `finishSettlement` / `retrySave` / `startNextHand` 编译失败。
- 跨街回归 RED：合法 check 转换后街道投入已归零，旧差值方案在现有协调器测试中触发 `chipArithmeticOverflow`。
- GREEN：`TableAnimationTests` 8 项、`SettlementPipelineTests` 3 项全部通过。

## 技术冲突与处理

一次合法的转换可以是 `actionApplied(check) → streetChanged → communityCardsDealt`，转换后 `committedThisStreet` 已因换街归零，因此不能用整个转换前后的街道投入直接相减。最终按协调裁决改为仅使用转换前的安全旁观快照与公开动作计算：`fold/check = 0`，`call = min(currentBet - committed, stack)`，`bet/raise = target - committed`，`allIn = stack`；所有减法均受检，不读取 UI 状态或隐藏底牌。

## 验证

- `swift test --filter TableAnimationTests --no-parallel`：8 项通过。
- `swift test --filter SettlementPipelineTests --no-parallel`：3 项通过。
- `swift test --no-parallel`：交付前复验 328 项通过，耗时 102.033 秒。
- `git diff --check`：通过。

## 自审

- 未将业务编号暴露到公开协调器 API；测试仓库仅从待保存的 `settlementReceipts` 记录尝试编号。
- 机器人底牌不进入公开事件或动画映射输入。
- 未改动既有事件顺序，暂停、旧版本机器人结果和行动者变更门禁的回归测试均通过。

## 审查修复

- 自动结算 RED：真实行动链结束后稳定复现协调器停在 `.botThinking`、存储停在 `.settlementPending`；GREEN 后成功自动到 `.awaitingNextHand`，`FailOnceSessionRepository` 自动到 `.saveFailed`。
- 保存管线现在先生成并缓存业务编号，再执行安全摊牌、投影和提交；可重试失败会用同一编号重跑完整流程。编号生成失败停在非重试 `.settling` 错误态。
- ID 测试生成器每次可返回不同值，最终断言仅调用一次，仓库从真实待写 `settlementReceipts` 观察到 `[firstID, firstID]`。
- 动画节奏 RED：注入记录首次观察到正常模式所有时长均为零；GREEN 后底牌 80ms、翻牌逐张 180ms、转牌/河牌 220ms、行动 250ms、底池/赢家 650ms，减少动态时同序列全为零。
- 补测未弃牌但安全观察无牌面的座位，保持两张牌背。
- 200 手性质测试改从自动保存后的 `StoredHandRecord` 审计，未删减动作合法性、机器人串行、两轮确定性和 36,000 筹码守恒断言。

## 审查修复验证

- `TableAnimationTests`：9 项通过。
- `SettlementPipelineTests`：7 项通过。
- `PokerCoordinatorTests`：51 项串行通过，耗时 77.508 秒。
- 全包 `--no-parallel`：交付前复验 333 项通过，耗时 132.335 秒。
