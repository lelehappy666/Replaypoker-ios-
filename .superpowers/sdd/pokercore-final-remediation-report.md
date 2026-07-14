# PokerCore 最终审查修正报告

## 结果

`DONE`

本轮仅修正 PokerCore 安全边界、牌堆解码、完成牌局归档和最终审查遗留测试；未开始机器人、会话持久化或 SwiftUI 功能接入。

## 实施内容

1. 将 `HoldemState`、`SeatState`、`Deck`、`EngineResult`、`HoldemEngine`、`BettingRules`、`StateValidator`、`GameEvent` 和带洗牌状态的 `SeededGenerator` 改为模块内部实现。
2. 新增唯一公开牌局门面 `HoldemGame`，对外只提供开局、执行动作、轮次推进、安全观察和已完成记录。`HoldemGame` 不遵循 `Codable`，不提供 checkpoint，并用空 `CustomReflectable` 结果阻断默认 Mirror 暴露。
3. 为 `Deck` 实现自定义 `Codable`，拒绝负索引、越界索引、非 52 张牌、重复/缺失/非法牌；`draw()` 对负内部索引防御性抛出规则错误。
4. `CompletedHandRecord` 构造前要求牌局完成并执行 `StateValidator.validate`；新增 `handRanksBySeat`、`finalStacks` 和有符号 `chipDeltas`，使用受检减法固化结果。
5. 增加独立非 `@testable` 公开 API 测试目标，验证外部调用方可开局、观察、行动和归档，且 Mirror 不暴露隐藏状态。
6. 补全合法 6 张牌最佳五张、两对多级比较、同花深层踢脚，以及空投入、全零投入、空底池奖励的直接测试。原“层乘法溢出”测试已改名为“相同层级投入汇总溢出”，生产代码已注明单层乘积与总投入的数学约束。

## TDD 证据

### RED

1. 先加入独立非 `@testable` 公开门面测试，运行：

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/pokercore-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/pokercore-module-cache swift test --disable-sandbox --package-path Packages/PokerCore --filter PokerCorePublicAPITests`

   exit code `1`；预期失败为 `cannot find 'HoldemGame' in scope`。
2. 为了独立确认另两个回归测试的 RED，从修正前基线 `6e3e4ff` 导出临时包到 `/tmp`，加入相同的损坏牌堆与伪造完成态断言，运行：

   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/pokercore-red-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/pokercore-red-module-cache swift test --disable-sandbox --package-path /tmp/pokercore-remediation-red --filter 'redDamagedDeck|redForgedCompletedState'`

   exit code `1`；共 `2` 项测试失败：负 `nextIndex` 解码未抛错，伪造 `awards` 的完成态仍被归档。

### GREEN

- 公开门面定向测试：`3` 项通过。
- 牌堆损坏、归档真实性及完整来源定向测试：通过。
- PokerCore 完整测试连续运行两次：每次 `136` 项通过、`0` 失败；500 种子属性测试每次均通过。

## 公开边界负向验证

用正常 `import PokerCore` 的临时编译探针引用 `Deck`、`HoldemState`、`SeatState`、`EngineResult`、`HoldemEngine`，并要求 `HoldemGame: Codable`。`swiftc -typecheck` 按预期 exit code `1`：五个完整状态类型均显示 `cannot find ... in scope`，`HoldemGame` 显示不遵循 `Encodable` / `Decodable`。探针随后删除，未进入仓库。

## 构建与差异验证

- `xcodegen generate`：exit code `0`，成功重建 `RiverClub.xcodeproj`。
- 通用 iOS 构建：

  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub -destination 'generic/platform=iOS' -derivedDataPath /tmp/RiverClub-PokerCore-Remediation CODE_SIGNING_ALLOWED=NO`

  首次在受限沙箱中因 SwiftPM/Clang 缓存无权限 exit code `74`（`Could not resolve package dependencies`）；按工具规则在沙箱外原命令重跑 exit code `0`，结果 `** TEST BUILD SUCCEEDED **`。
- `git diff --check`：exit code `0`。
- 最终 `git status --short`：报告写入前工作树干净。

## 提交

- `96c7951 fix: 封闭牌局隐藏状态并强化归档校验`
- `d6378bf test: 补全牌型与底池边界覆盖`

## 剩余顾虑

- 本阶段按简报明确不提供牌局 checkpoint；后续会话持久化必须另行设计可信恢复边界，不得重新公开完整状态图或洗牌种子。
- `HoldemGame` 是可变引用类型且故意不声明 `Sendable`；应用层将来需在单一 actor/串行上下文中持有和调用。
