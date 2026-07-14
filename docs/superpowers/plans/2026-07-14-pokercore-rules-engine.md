# PokerCore 德州扑克规则引擎实施计划

> **面向智能开发代理：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务执行本计划。所有步骤使用复选框跟踪。

**目标：** 构建一个可独立运行和测试的纯 Swift 九人无限注德州扑克规则包，覆盖确定性洗牌、牌型、合法动作、下注轮次、全下、任意边池、摊牌和筹码守恒。

**架构：** 新建本地 Swift Package `PokerCore`，以不可变状态转换语义的 `HoldemState` 和纯函数 `HoldemEngine.applying(_:by:to:)` 为核心。规则包不依赖 SwiftUI、数据库、系统时间或当前 iOS 应用模型，通过领域事件向后续会话层暴露所有状态变化。

**技术栈：** Swift 6、Swift Package Manager、Foundation、Swift Testing；无第三方依赖。

## 全局约束

- 规则类型必须符合 `Sendable`；需要保存的状态同时符合 `Codable`。
- 所有筹码和下注金额使用非负 `Int`，不得使用浮点数。
- 随机行为必须由显式种子驱动；相同种子与动作序列必须得到相同结果。
- 机器人或 UI 不得通过本包公开接口读取其他玩家底牌、剩余牌堆或未来随机结果。
- 支持 2–9 名参与者；首个 UI 使用 9 人桌。
- 只实现无限注德州扑克，不实现奥马哈、短牌或固定限注。
- 一手中的 52 张牌不得重复，任何已提交状态不得出现负筹码。
- 任意结算后，座位筹码加未分配底池必须满足筹码守恒。
- 测试命令优先使用 `swift test --package-path Packages/PokerCore`，不依赖 iOS 模拟器。
- 每个任务严格执行 RED → GREEN → REFACTOR，并单独提交。

## 文件结构

```text
Packages/PokerCore/
├── Package.swift
├── Sources/PokerCore/
│   ├── Cards/Card.swift                 花色、点数、牌
│   ├── Cards/Deck.swift                 确定性牌组
│   ├── Cards/SeededGenerator.swift      可保存随机数状态
│   ├── Evaluation/HandRank.swift        可比较牌型
│   ├── Evaluation/HandEvaluator.swift   七选五评估
│   ├── Game/BettingRules.swift          合法动作和最小加注
│   ├── Game/GameAction.swift            玩家动作
│   ├── Game/GameEvent.swift             领域事件
│   ├── Game/HoldemEngine.swift          纯状态转换入口
│   ├── Game/HoldemState.swift           完整规则状态
│   ├── Game/PotBuilder.swift            主池和边池
│   ├── Game/SeatState.swift             座位状态
│   └── Validation/StateValidator.swift  状态不变量
└── Tests/PokerCoreTests/
    ├── BettingRulesTests.swift
    ├── DeckTests.swift
    ├── HandEvaluatorTests.swift
    ├── HoldemEngineTests.swift
    ├── PotBuilderTests.swift
    ├── StatePropertyTests.swift
    └── TestSupport.swift                 仅测试使用的牌面解析和状态构造器
```

---

### 任务 1：建立独立 Swift Package 与基础领域类型

**文件：**
- 创建：`Packages/PokerCore/Package.swift`
- 创建：`Packages/PokerCore/Sources/PokerCore/Cards/Card.swift`
- 创建：`Packages/PokerCore/Sources/PokerCore/Game/GameAction.swift`
- 创建：`Packages/PokerCore/Sources/PokerCore/Game/SeatState.swift`
- 创建：`Packages/PokerCore/Tests/PokerCoreTests/CardTests.swift`
- 创建：`Packages/PokerCore/Tests/PokerCoreTests/TestSupport.swift`

**接口：**
- 产出：`Suit`、`Rank`、`Card`、`SeatID`、`Chips`、`PlayerAction`、`SeatState`。
- 约束：`SeatID.rawValue` 只能为 `0...8`；`Chips` 初始化负数时抛出 `PokerRuleError.negativeChips`。

- [ ] **步骤 1：先写基础类型失败测试**

```swift
import Testing
@testable import PokerCore

@Test func cardsHaveStableComparableOrder() {
    #expect(Card(rank: .ace, suit: .spades) > Card(rank: .king, suit: .hearts))
    #expect(Set(Card.fullDeck).count == 52)
}

@Test func chipsRejectNegativeAmounts() {
    #expect(throws: PokerRuleError.negativeChips) { try Chips(-1) }
}

@Test func seatIDsRejectValuesOutsideNineSeatTable() {
    #expect(throws: PokerRuleError.invalidSeat) { try SeatID(9) }
}
```

- [ ] **步骤 2：运行测试并确认 RED**

运行：

```bash
swift test --package-path Packages/PokerCore --filter CardTests
```

预期：编译失败，提示找不到 `PokerCore` 或上述类型。

- [ ] **步骤 3：创建包和最小领域类型**

`Package.swift` 必须声明 macOS 14 和 iOS 18，并只暴露一个 `PokerCore` library。基础类型使用以下签名：

```swift
public enum PokerRuleError: Error, Equatable, Sendable {
    case negativeChips
    case invalidSeat
    case deckExhausted
    case invalidCards
    case insufficientPlayers
    case illegalAction(String)
    case invalidState(String)
}

public struct Chips: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public let rawValue: Int
    public init(_ value: Int) throws {
        guard value >= 0 else { throw PokerRuleError.negativeChips }
        rawValue = value
    }
    public init?(rawValue: Int) { guard rawValue >= 0 else { return nil }; self.rawValue = rawValue }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct SeatID: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public let rawValue: Int
    public init(_ value: Int) throws {
        guard (0...8).contains(value) else { throw PokerRuleError.invalidSeat }
        rawValue = value
    }
    public init?(rawValue: Int) { guard (0...8).contains(rawValue) else { return nil }; self.rawValue = rawValue }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum Suit: Int, CaseIterable, Codable, Sendable { case clubs, diamonds, hearts, spades }
public enum Rank: Int, CaseIterable, Codable, Comparable, Sendable {
    case two = 2, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct Card: Codable, Hashable, Comparable, Sendable {
    public let rank: Rank
    public let suit: Suit
    public static let fullDeck = Suit.allCases.flatMap { suit in Rank.allCases.map { Card(rank: $0, suit: suit) } }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank == rhs.rank ? lhs.suit.rawValue < rhs.suit.rawValue : lhs.rank < rhs.rank
    }
}

public struct SeatState: Codable, Equatable, Sendable {
    public let id: SeatID
    public var stack: Chips
    public var committedThisStreet: Chips
    public var committedThisHand: Chips
    public var holeCards: [Card]
    public var hasFolded: Bool
    public var isAllIn: Bool
    public var isSittingOut: Bool
}
```

`PlayerAction` 精确定义为 `.fold`、`.check`、`.call`、`.bet(Chips)`、`.raiseTo(Chips)`、`.allIn`。`SeatState` 保存 `id`、`stack`、`committedThisStreet`、`committedThisHand`、`holeCards`、`hasFolded`、`isAllIn`、`isSittingOut`。

`TestSupport.swift` 定义 `Cards.parse(_:) throws -> [Card]`，使用空格分隔两字符牌面，点数支持 `2...9/T/J/Q/K/A`，花色支持 `c/d/h/s`；遇到非法长度、点数或花色时抛出 `PokerRuleError.invalidCards`。

- [ ] **步骤 4：运行基础测试并确认 GREEN**

运行：`swift test --package-path Packages/PokerCore --filter CardTests`  
预期：全部通过，且无并发安全警告。

- [ ] **步骤 5：提交任务 1**

```bash
git add Packages/PokerCore
git commit -m "feat: add PokerCore domain types"
```

---

### 任务 2：实现可保存的确定性洗牌与发牌

**文件：**
- 创建：`Packages/PokerCore/Sources/PokerCore/Cards/SeededGenerator.swift`
- 创建：`Packages/PokerCore/Sources/PokerCore/Cards/Deck.swift`
- 创建：`Packages/PokerCore/Tests/PokerCoreTests/DeckTests.swift`

**接口：**
- 产出：`SeededGenerator.init(seed:)`、`Deck.shuffled(seed:)`、`mutating Deck.draw()`。
- `Deck` 必须 `Codable`，恢复后继续发牌不能改变顺序。

- [ ] **步骤 1：编写确定性和唯一性失败测试**

```swift
@Test func equalSeedsProduceEqualDecks() throws {
    var first = Deck.shuffled(seed: 42)
    var second = Deck.shuffled(seed: 42)
    #expect(try (0..<52).map { _ in try first.draw() } == (0..<52).map { _ in try second.draw() })
}

@Test func drawingWholeDeckProducesEveryCardExactlyOnce() throws {
    var deck = Deck.shuffled(seed: 7)
    let cards = try (0..<52).map { _ in try deck.draw() }
    #expect(Set(cards).count == 52)
    #expect(throws: PokerRuleError.deckExhausted) { try deck.draw() }
}

@Test func encodedDeckResumesAtSamePosition() throws {
    var deck = Deck.shuffled(seed: 99)
    _ = try deck.draw()
    let restored = try JSONDecoder().decode(Deck.self, from: JSONEncoder().encode(deck))
    var lhs = deck
    var rhs = restored
    #expect(try lhs.draw() == rhs.draw())
}
```

- [ ] **步骤 2：运行测试并确认 RED**

运行：`swift test --package-path Packages/PokerCore --filter DeckTests`  
预期：编译失败，提示 `Deck` 和 `deckExhausted` 未定义。

- [ ] **步骤 3：实现随机数与 Fisher–Yates 洗牌**

```swift
public struct SeededGenerator: RandomNumberGenerator, Codable, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public struct Deck: Codable, Equatable, Sendable {
    private var cards: [Card]
    private var nextIndex: Int

    public static func shuffled(seed: UInt64) -> Self {
        var cards = Card.fullDeck
        var generator = SeededGenerator(seed: seed)
        cards.shuffle(using: &generator)
        return Self(cards: cards, nextIndex: 0)
    }

    public mutating func draw() throws -> Card {
        guard nextIndex < cards.count else { throw PokerRuleError.deckExhausted }
        defer { nextIndex += 1 }
        return cards[nextIndex]
    }

    public var remainingCards: [Card] { Array(cards[nextIndex...]) }
}
```

- [ ] **步骤 4：运行 Deck 和全包测试**

运行：`swift test --package-path Packages/PokerCore`  
预期：任务 1–2 测试全部通过。

- [ ] **步骤 5：提交任务 2**

```bash
git add Packages/PokerCore
git commit -m "feat: add deterministic poker deck"
```

---

### 任务 3：实现七选五牌型评估

**文件：**
- 创建：`Packages/PokerCore/Sources/PokerCore/Evaluation/HandRank.swift`
- 创建：`Packages/PokerCore/Sources/PokerCore/Evaluation/HandEvaluator.swift`
- 创建：`Packages/PokerCore/Tests/PokerCoreTests/HandEvaluatorTests.swift`

**接口：**
- 产出：`HandCategory`、`HandRank`、`HandEvaluator.best(of:) throws -> HandRank`。
- `HandRank` 的比较必须先比较类别，再按从高到低的五个比较点数比较。

- [ ] **步骤 1：编写牌型、踢脚和轮子顺子失败测试**

```swift
private struct CategoryCase: Sendable {
    let source: String
    let category: HandCategory
}

@Test(arguments: [
    CategoryCase(source: "As Ks Qs Js Ts 2d 3c", category: .straightFlush),
    CategoryCase(source: "Ah Ad Ac As Kd 2c 3h", category: .fourOfAKind),
    CategoryCase(source: "Kh Kd Kc 2s 2d 8c 9h", category: .fullHouse),
    CategoryCase(source: "As 9s 7s 4s 2s Kd Qh", category: .flush),
    CategoryCase(source: "5s 4d 3c 2h As Kd Qh", category: .straight),
]) func recognizesCategories(example: CategoryCase) throws {
    #expect(try HandEvaluator.best(of: Cards.parse(example.source)).category == example.category)
}

@Test func comparesKickersAfterPair() throws {
    let aceKicker = try HandEvaluator.best(of: Cards.parse("Ah Ad Ks Qc 9s 3d 2c"))
    let kingKicker = try HandEvaluator.best(of: Cards.parse("Ah Ad Ks Jc 9s 3d 2c"))
    #expect(aceKicker > kingKicker)
}

@Test func wheelStraightRanksAsFiveHigh() throws {
    let wheel = try HandEvaluator.best(of: Cards.parse("As 2d 3c 4h 5s Kd Qh"))
    #expect(wheel.tieBreak == [5])
}
```

测试目录创建仅供测试使用的 `Cards.parse(_:)`，把两字符牌面解析为 `Card`，解析失败直接抛出测试错误。

- [ ] **步骤 2：运行评估测试并确认 RED**

运行：`swift test --package-path Packages/PokerCore --filter HandEvaluatorTests`  
预期：编译失败，提示 `HandEvaluator` 未定义。

- [ ] **步骤 3：实现完整五张评估和七选五**

```swift
public enum HandCategory: Int, Codable, Comparable, Sendable {
    case highCard, onePair, twoPair, threeOfAKind, straight, flush, fullHouse, fourOfAKind, straightFlush
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct HandRank: Codable, Equatable, Comparable, Sendable {
    public let category: HandCategory
    public let tieBreak: [Int]
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.category == rhs.category
            ? lhs.tieBreak.lexicographicallyPrecedes(rhs.tieBreak)
            : lhs.category < rhs.category
    }
}

public enum HandEvaluator {
    public static func best(of cards: [Card]) throws -> HandRank {
        guard (5...7).contains(cards.count), Set(cards).count == cards.count else {
            throw PokerRuleError.invalidCards
        }
        return combinations(of: cards, taking: 5).map(evaluateFive).max()!
    }
}
```

`evaluateFive` 必须按以下次序返回比较数组：四条 `[四条, 踢脚]`；葫芦 `[三条, 对子]`；同花和高牌返回五个降序点数；顺子和同花顺返回最高点数且 A2345 返回 `[5]`；三条 `[三条, 两个踢脚]`；两对 `[高对, 低对, 踢脚]`；一对 `[对子, 三个踢脚]`。

- [ ] **步骤 4：运行牌型测试**

运行：`swift test --package-path Packages/PokerCore --filter HandEvaluatorTests`  
预期：所有参数化牌型、踢脚、轮子顺子和重复牌拒绝测试通过。

- [ ] **步骤 5：提交任务 3**

```bash
git add Packages/PokerCore
git commit -m "feat: evaluate Texas Holdem hands"
```

---

### 任务 4：实现下注状态、合法动作和最小加注

**文件：**
- 创建：`Packages/PokerCore/Sources/PokerCore/Game/HoldemState.swift`
- 创建：`Packages/PokerCore/Sources/PokerCore/Game/BettingRules.swift`
- 创建：`Packages/PokerCore/Tests/PokerCoreTests/BettingRulesTests.swift`
- 修改：`Packages/PokerCore/Tests/PokerCoreTests/TestSupport.swift`

**接口：**
- 产出：`Street`、`HandConfig`、`HoldemState`、`LegalActionSet`、`BettingRules.legalActions(for:in:)`。
- `LegalActionSet` 明确包含 `callAmount`、`minimumRaiseTo`、`maximumRaiseTo`。

- [ ] **步骤 1：编写过牌、跟注、最小加注和短码全下失败测试**

```swift
@Test func unopenedPotAllowsCheckOrBet() throws {
    let state = Fixtures.bettingState(currentBet: 0, seatCommitment: 0, stack: 1_000, lastFullRaise: 100)
    let legal = try BettingRules.legalActions(for: SeatID(0), in: state)
    #expect(legal.canCheck)
    #expect(legal.minimumBet == Chips(rawValue: 100)!)
}

@Test func facingBetAllowsFoldCallAndFullRaise() throws {
    let state = Fixtures.bettingState(currentBet: 300, seatCommitment: 100, stack: 1_000, lastFullRaise: 200)
    let legal = try BettingRules.legalActions(for: SeatID(0), in: state)
    #expect(legal.callAmount == Chips(rawValue: 200)!)
    #expect(legal.minimumRaiseTo == Chips(rawValue: 500)!)
    #expect(legal.maximumRaiseTo == Chips(rawValue: 1_100))
}

@Test func shortAllInDoesNotReopenRaising() throws {
    let state = Fixtures.shortAllInAfterFullRaise()
    #expect(try BettingRules.legalActions(for: SeatID(0), in: state).canRaise == false)
}
```

- [ ] **步骤 2：运行下注测试并确认 RED**

运行：`swift test --package-path Packages/PokerCore --filter BettingRulesTests`  
预期：编译失败，提示下注状态和规则未定义。

- [ ] **步骤 3：实现精确下注接口**

```swift
public enum Street: Int, Codable, Sendable { case preflop, flop, turn, river, showdown, complete }

public struct HandConfig: Codable, Equatable, Sendable {
    public let smallBlind: Chips
    public let bigBlind: Chips
    public let dealer: SeatID
    public init(smallBlind: Chips, bigBlind: Chips, dealer: SeatID) throws {
        guard smallBlind.rawValue > 0, bigBlind.rawValue >= smallBlind.rawValue * 2 else {
            throw PokerRuleError.invalidState("invalid blinds")
        }
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.dealer = dealer
    }
}

public struct RecordedAction: Codable, Equatable, Sendable {
    public let seat: SeatID
    public let street: Street
    public let action: PlayerAction
}

public struct Pot: Codable, Equatable, Sendable {
    public let amount: Chips
    public let eligible: Set<SeatID>
}

public struct HoldemState: Codable, Equatable, Sendable {
    public var config: HandConfig
    public var deck: Deck
    public var seats: [SeatState]
    public var dealer: SeatID
    public var smallBlindSeat: SeatID
    public var bigBlindSeat: SeatID
    public var currentActor: SeatID?
    public var street: Street
    public var communityCards: [Card]
    public var currentBet: Chips
    public var lastFullRaiseSize: Chips
    public var actedSinceLastFullRaise: Set<SeatID>
    public var actionHistory: [RecordedAction]
    public var settledPots: [Pot]
    public var awards: [SeatID: Chips]
    public var unallocatedPot: Chips
    public let initialTotalChips: Int

    public var handCommitments: [SeatID: Chips] {
        Dictionary(uniqueKeysWithValues: seats.map { ($0.id, $0.committedThisHand) })
    }
    public var foldedSeats: Set<SeatID> { Set(seats.filter(\.hasFolded).map(\.id)) }
    public var activeSeats: [SeatState] { seats.filter { !$0.hasFolded && !$0.isSittingOut } }
    public var dealtInSeats: [SeatState] { seats.filter { !$0.holeCards.isEmpty } }
    public var totalSeatChips: Int { seats.reduce(0) { $0 + $1.stack.rawValue } }
    public func canAct(_ id: SeatID) -> Bool {
        seats.contains { $0.id == id && !$0.hasFolded && !$0.isAllIn && !$0.isSittingOut }
    }
}

public struct LegalActionSet: Equatable, Sendable {
    public let canFold: Bool
    public let canCheck: Bool
    public let callAmount: Chips?
    public let minimumBet: Chips?
    public let minimumRaiseTo: Chips?
    public let maximumRaiseTo: Chips?
    public let canAllIn: Bool
    public var canRaise: Bool { minimumRaiseTo != nil }
}

public enum BettingRules {
    public static func legalActions(for seat: SeatID, in state: HoldemState) throws -> LegalActionSet
    public static func applying(_ action: PlayerAction, by seat: SeatID, to state: HoldemState) throws -> HoldemState
}
```

实现必须区分“完整加注”和“低于完整加注的短码全下”。只有完整加注才更新 `lastFullRaiseSize` 并重新开放已行动玩家的加注权；跟注金额等于 `min(currentBet - committedThisStreet, stack)`。

`TestSupport.swift` 在本任务增加 `Fixtures.bettingState(currentBet:seatCommitment:stack:lastFullRaise:) -> HoldemState` 和 `Fixtures.shortAllInAfterFullRaise() -> HoldemState`，固定使用 50/100 盲注、庄位 8，并创建满足 `StateValidator` 前置条件的九座状态。

- [ ] **步骤 4：运行下注规则和全包测试**

运行：`swift test --package-path Packages/PokerCore`  
预期：非法低额加注不改变输入状态；短码全下、完整加注和封闭行动测试全部通过。

- [ ] **步骤 5：提交任务 4**

```bash
git add Packages/PokerCore
git commit -m "feat: validate no-limit betting actions"
```

---

### 任务 5：实现开局、盲注、发牌与下注轮次推进

**文件：**
- 创建：`Packages/PokerCore/Sources/PokerCore/Game/GameEvent.swift`
- 创建：`Packages/PokerCore/Sources/PokerCore/Game/HoldemEngine.swift`
- 创建：`Packages/PokerCore/Tests/PokerCoreTests/HoldemEngineTests.swift`
- 修改：`Packages/PokerCore/Tests/PokerCoreTests/TestSupport.swift`

**接口：**
- 产出：`HoldemEngine.start(config:stacks:seed:)`、`HoldemEngine.applying(_:by:to:)`、`EngineResult`、`GameEvent`。
- `EngineResult` 同时返回新状态和按发生顺序排列的事件。

- [ ] **步骤 1：编写九人桌、单挑和街道推进失败测试**

```swift
@Test func nineSeatHandPostsBlindsDealsTwoCardsAndActsLeftOfBigBlind() throws {
    let config = try HandConfig(smallBlind: Chips(50), bigBlind: Chips(100), dealer: SeatID(0))
    let result = try HoldemEngine.start(config: config, stacks: Fixtures.nineStacks(10_000), seed: 1)
    #expect(result.state.seats.allSatisfy { $0.holeCards.count == 2 })
    #expect(result.state.currentActor == SeatID(rawValue: 3)!)
    #expect(result.events.contains(.blindPosted(seat: SeatID(rawValue: 1)!, amount: Chips(rawValue: 50)!)))
}

@Test func headsUpDealerPostsSmallBlindAndActsFirstPreflop() throws {
    let config = try HandConfig(smallBlind: Chips(50), bigBlind: Chips(100), dealer: SeatID(0))
    let result = try HoldemEngine.start(config: config, stacks: Fixtures.twoStacks(10_000), seed: 1)
    #expect(result.state.dealer == result.state.smallBlindSeat)
    #expect(result.state.currentActor == result.state.dealer)
}

@Test func completedPreflopDealsExactlyThreeFlopCards() throws {
    let state = try Fixtures.completePreflopState()
    let result = try HoldemEngine.advanceIfRoundComplete(state)
    #expect(result.state.street == .flop)
    #expect(result.state.communityCards.count == 3)
}
```

- [ ] **步骤 2：运行引擎测试并确认 RED**

运行：`swift test --package-path Packages/PokerCore --filter HoldemEngineTests`  
预期：编译失败，提示 `HoldemEngine` 未定义。

- [ ] **步骤 3：实现引擎入口和事件**

```swift
public struct EngineResult: Equatable, Sendable {
    public let state: HoldemState
    public let events: [GameEvent]
}

public enum GameEvent: Equatable, Sendable {
    case handStarted(seed: UInt64)
    case blindPosted(seat: SeatID, amount: Chips)
    case holeCardsDealt(seat: SeatID)
    case actionApplied(seat: SeatID, action: PlayerAction)
    case streetChanged(Street)
    case communityCardsDealt([Card])
    case potCreated(Pot)
    case potAwarded(potIndex: Int, winners: [SeatID], amounts: [SeatID: Chips])
    case handCompleted
}

public enum HoldemEngine {
    public static func start(config: HandConfig, stacks: [SeatID: Chips], seed: UInt64) throws -> EngineResult
    public static func applying(_ action: PlayerAction, by seat: SeatID, to state: HoldemState) throws -> EngineResult
    public static func advanceIfRoundComplete(_ state: HoldemState) throws -> EngineResult
}
```

发牌顺序从庄位左侧第一个在座玩家开始，每人一张、循环两次。翻牌前从大盲左侧行动；翻牌后从庄位左侧第一个未弃牌且未全下玩家行动。若剩余所有未弃牌玩家均全下，自动依次发完公共牌并进入摊牌。

`TestSupport.swift` 在本任务增加 `Fixtures.nineStacks(_:)`、`Fixtures.twoStacks(_:)`、`Fixtures.completePreflopState()`；前两个按 SeatID 升序创建相同筹码，后者通过公开 `HoldemEngine.applying` 连续过牌/跟注得到下注轮次刚结束的真实状态，不直接篡改私有字段。

- [ ] **步骤 4：运行引擎测试**

运行：`swift test --package-path Packages/PokerCore --filter HoldemEngineTests`  
预期：九人、单挑、弃牌跳座、自动发完公共牌和四条街推进测试通过。

- [ ] **步骤 5：提交任务 5**

```bash
git add Packages/PokerCore
git commit -m "feat: run deterministic Holdem betting rounds"
```

---

### 任务 6：实现主池、任意边池和奇数筹码

**文件：**
- 创建：`Packages/PokerCore/Sources/PokerCore/Game/PotBuilder.swift`
- 创建：`Packages/PokerCore/Tests/PokerCoreTests/PotBuilderTests.swift`
- 修改：`Packages/PokerCore/Tests/PokerCoreTests/TestSupport.swift`

**接口：**
- 产出：`Pot`、`PotBuilder.build(from:)`、`PotBuilder.awards(for:ranks:dealer:)`。
- 弃牌玩家投入计入底池，但不能成为该池赢家。

- [ ] **步骤 1：编写多边池和奇数筹码失败测试**

```swift
@Test func buildsMainAndTwoSidePots() throws {
    let commitments: [SeatID: Int] = [0: 100, 1: 300, 2: 500, 3: 500].seatMap
    let folded: Set<SeatID> = [SeatID(rawValue: 3)!]
    let pots = try PotBuilder.build(commitments: commitments.chips, folded: folded)
    #expect(pots.map(\.amount.rawValue) == [400, 600, 400])
    #expect(pots[0].eligible == [0, 1, 2].seatSet)
    #expect(pots[2].eligible == [2].seatSet)
}

@Test func oddChipMovesClockwiseFromDealer() throws {
    let pot = Pot(amount: Chips(rawValue: 101)!, eligible: [0, 2].seatSet)
    let awards = try PotBuilder.awards(for: [pot], ranks: Fixtures.tiedRanks([0, 2]), dealer: SeatID(rawValue: 8)!)
    #expect(awards[SeatID(rawValue: 0)!]?.rawValue == 51)
    #expect(awards[SeatID(rawValue: 2)!]?.rawValue == 50)
}
```

- [ ] **步骤 2：运行边池测试并确认 RED**

运行：`swift test --package-path Packages/PokerCore --filter PotBuilderTests`  
预期：编译失败，提示 `PotBuilder` 未定义。

- [ ] **步骤 3：实现分层底池算法**

```swift
public enum PotBuilder {
    public static func build(commitments: [SeatID: Chips], folded: Set<SeatID>) throws -> [Pot]
    public static func awards(
        for pots: [Pot],
        ranks: [SeatID: HandRank],
        dealer: SeatID
    ) throws -> [SeatID: Chips]
}
```

构建算法按所有非零投入的不同额度升序切层；每层金额为“本层差额 × 尚有投入的玩家数”。资格集合排除弃牌者。平分时先整数除法，剩余奇数筹码按庄位左侧开始的座位顺序逐个发放。

`TestSupport.swift` 在本任务增加仅测试使用的 `[Int: Int].seatMap`、`[SeatID: Int].chips`、`[Int].seatSet` 和 `Fixtures.tiedRanks(_:)`，所有转换都通过 `try SeatID` 与 `try Chips`，转换失败立即让测试失败。

- [ ] **步骤 4：运行边池和全包测试**

运行：`swift test --package-path Packages/PokerCore`  
预期：一至三个底池、弃牌投入、平分、多个奇数筹码和总额守恒测试全部通过。

- [ ] **步骤 5：提交任务 6**

```bash
git add Packages/PokerCore
git commit -m "feat: settle main and side pots"
```

---

### 任务 7：完成摊牌、结算和整手状态机

**文件：**
- 修改：`Packages/PokerCore/Sources/PokerCore/Game/HoldemEngine.swift`
- 修改：`Packages/PokerCore/Sources/PokerCore/Game/HoldemState.swift`
- 修改：`Packages/PokerCore/Tests/PokerCoreTests/HoldemEngineTests.swift`
- 修改：`Packages/PokerCore/Tests/PokerCoreTests/TestSupport.swift`

**接口：**
- 产出：完整 `HoldemEngine`，一手最终进入 `.complete`，底池归零并更新座位筹码。
- 结算事件必须包含每个底池、赢家和获得金额，供后续永久牌局记录使用。

- [ ] **步骤 1：编写弃牌获胜、摊牌和平分失败测试**

```swift
@Test func lastRemainingPlayerWinsWithoutShowingOtherCards() throws {
    let result = try Fixtures.playUntilEveryoneButSeatZeroFolds()
    #expect(result.state.street == .complete)
    #expect(Set(result.state.awards.keys) == Set([SeatID(rawValue: 0)!]))
    #expect(result.state.totalSeatChips == result.state.initialTotalChips)
}

@Test func showdownAwardsEverySidePotToBestEligibleHand() throws {
    let result = try Fixtures.resolveThreeWayAllInWithTwoSidePots()
    #expect(result.events.filter(\.isPotAward).count == 3)
    #expect(result.state.unallocatedPot.rawValue == 0)
    #expect(result.state.totalSeatChips == Fixtures.initialTotalChips)
}

@Test func exactTieSplitsPotAndPreservesTotalChips() throws {
    let result = try Fixtures.resolveBoardPlayingTie()
    #expect(result.state.totalSeatChips == Fixtures.initialTotalChips)
    #expect(result.state.street == .complete)
}
```

- [ ] **步骤 2：运行整手测试并确认 RED**

运行：`swift test --package-path Packages/PokerCore --filter HoldemEngineTests`  
预期：结算断言失败，因为引擎尚未更新筹码或清空底池。

- [ ] **步骤 3：实现摊牌与结算路径**

结算顺序必须固定：构建底池 → 为每个未弃牌座位评估七张牌 → 分别选出每个池的最高合法牌型 → 按庄位顺序分配奇数筹码 → 更新筹码 → 生成 `potAwarded` 事件 → 将街道置为 `.complete`。只有一名未弃牌玩家时跳过牌型评估，但仍按同一底池分配接口结算。

```swift
private static func settle(_ state: HoldemState) throws -> EngineResult {
    let pots = try PotBuilder.build(commitments: state.handCommitments, folded: state.foldedSeats)
    let ranks = try state.activeSeats.reduce(into: [SeatID: HandRank]()) { result, seat in
        result[seat.id] = try HandEvaluator.best(of: seat.holeCards + state.communityCards)
    }
    let awards = try PotBuilder.awards(for: pots, ranks: ranks, dealer: state.dealer)
    return try state.completingHand(pots: pots, awards: awards, ranks: ranks)
}
```

`TestSupport.swift` 在本任务增加 `playUntilEveryoneButSeatZeroFolds()`、`resolveThreeWayAllInWithTwoSidePots()` 和 `resolveBoardPlayingTie()`；三者必须从 `HoldemEngine.start` 开始并只调用公开动作接口构造结果，不能直接伪造完成状态。

- [ ] **步骤 4：运行全包测试**

运行：`swift test --package-path Packages/PokerCore`  
预期：所有规则、牌型、下注、边池和完整牌局测试通过。

- [ ] **步骤 5：提交任务 7**

```bash
git add Packages/PokerCore
git commit -m "feat: complete Holdem showdown settlement"
```

---

### 任务 8：加入状态验证器和属性测试

**文件：**
- 创建：`Packages/PokerCore/Sources/PokerCore/Validation/StateValidator.swift`
- 创建：`Packages/PokerCore/Tests/PokerCoreTests/StatePropertyTests.swift`
- 修改：`Packages/PokerCore/Sources/PokerCore/Game/HoldemEngine.swift`

**接口：**
- 产出：`StateValidator.validate(_:) throws`。
- 引擎每个公开转换入口在 DEBUG 测试构建中验证输入与输出状态。

- [ ] **步骤 1：编写损坏状态和 500 个随机牌局失败测试**

```swift
@Test func validatorRejectsDuplicateVisibleCards() throws {
    let state = Fixtures.stateWithDuplicateCard()
    #expect(throws: PokerRuleError.invalidState("duplicate cards")) {
        try StateValidator.validate(state)
    }
}

@Test func fiveHundredSeededHandsPreserveCoreInvariants() throws {
    for seed in 1...500 {
        let result = try Simulation.playLegalHand(seed: UInt64(seed), playerCount: 2 + seed % 8)
        try StateValidator.validate(result.state)
        #expect(result.state.street == .complete)
        #expect(result.state.totalSeatChips == result.initialTotalChips)
        #expect(Set(result.allDealtCards).count == result.allDealtCards.count)
    }
}
```

- [ ] **步骤 2：运行属性测试并确认 RED**

运行：`swift test --package-path Packages/PokerCore --filter StatePropertyTests`  
预期：编译失败，提示 `StateValidator` 未定义。

- [ ] **步骤 3：实现验证器和合法动作模拟器**

```swift
public enum StateValidator {
    public static func validate(_ state: HoldemState) throws {
        let allCards = state.seats.flatMap(\.holeCards) + state.communityCards + state.deck.remainingCards
        guard allCards.count == 52, Set(allCards).count == 52 else {
            throw PokerRuleError.invalidState("duplicate cards")
        }
        guard state.seats.allSatisfy({ $0.stack.rawValue >= 0 }) else {
            throw PokerRuleError.invalidState("negative stack")
        }
        guard state.totalSeatChips + state.unallocatedPot.rawValue == state.initialTotalChips else {
            throw PokerRuleError.invalidState("chip conservation")
        }
        guard state.currentActor == nil || state.currentActor.map(state.canAct) == true else {
            throw PokerRuleError.invalidState("invalid actor")
        }
    }
}
```

测试中的 `Simulation.playLegalHand` 每次只从 `BettingRules.legalActions` 返回的集合中按种子选择动作；连续 500 手必须在测试默认超时内完成，出现首个失败种子时输出种子和动作序列。

- [ ] **步骤 4：运行完整测试两次确认确定性**

运行两次：

```bash
swift test --package-path Packages/PokerCore
swift test --package-path Packages/PokerCore
```

预期：两次测试数量和结果相同，500 个种子全部通过，无随机失败。

- [ ] **步骤 5：提交任务 8**

```bash
git add Packages/PokerCore
git commit -m "test: verify PokerCore state invariants"
```

---

### 任务 9：为后续应用接入稳定公开接口

**文件：**
- 创建：`Packages/PokerCore/Sources/PokerCore/Game/PublicSnapshot.swift`
- 创建：`Packages/PokerCore/Tests/PokerCoreTests/PublicSnapshotTests.swift`
- 修改：`Packages/PokerCore/Package.swift`
- 修改：`project.yml`

**接口：**
- 产出：`PlayerObservation`、`SpectatorObservation`、`CompletedHandRecord`。
- `PlayerObservation` 只包含指定座位自己的底牌；`CompletedHandRecord` 才包含所有已获发底牌玩家的最终底牌。

- [ ] **步骤 1：编写隐藏信息边界失败测试**

```swift
@Test func playerObservationContainsOnlyOwnHoleCards() throws {
    let state = try Fixtures.startedNineSeatState()
    let observation = try PlayerObservation(state: state, viewer: SeatID(rawValue: 0)!)
    #expect(observation.ownHoleCards.count == 2)
    #expect(Mirror(reflecting: observation).children.contains { $0.label == "deck" } == false)
    #expect(Mirror(reflecting: observation).children.contains { $0.label == "opponentHoleCards" } == false)
}

@Test func completedRecordContainsFoldedPlayersCards() throws {
    let state = try Fixtures.completedHandWithFoldedPlayers()
    let record = try CompletedHandRecord(state: state)
    #expect(record.holeCardsBySeat.count == state.dealtInSeats.count)
    #expect(record.holeCardsBySeat[state.firstFoldedSeat]?.count == 2)
}

@Test func incompleteHandCannotCreateHistoryRecord() throws {
    let state = try Fixtures.startedNineSeatState()
    #expect(throws: PokerRuleError.illegalAction("hand not complete")) {
        try CompletedHandRecord(state: state)
    }
}
```

- [ ] **步骤 2：运行公开接口测试并确认 RED**

运行：`swift test --package-path Packages/PokerCore --filter PublicSnapshotTests`  
预期：编译失败，提示观察与记录类型未定义。

- [ ] **步骤 3：实现最小公开快照并接入 XcodeGen**

```swift
public struct PlayerObservation: Equatable, Sendable {
    public let viewer: SeatID
    public let ownHoleCards: [Card]
    public let communityCards: [Card]
    public let publicSeats: [PublicSeat]
    public let legalActions: LegalActionSet?
    public let events: [GameEvent]
    public init(state: HoldemState, viewer: SeatID) throws {
        guard let seat = state.seats.first(where: { $0.id == viewer }) else {
            throw PokerRuleError.invalidSeat
        }
        self.viewer = viewer
        ownHoleCards = seat.holeCards
        communityCards = state.communityCards
        publicSeats = state.seats.map(PublicSeat.init)
        legalActions = state.currentActor == viewer
            ? try BettingRules.legalActions(for: viewer, in: state)
            : nil
        events = state.actionHistory.map { .actionApplied(seat: $0.seat, action: $0.action) }
    }
}

public struct PublicSeat: Equatable, Sendable {
    public let id: SeatID
    public let stack: Chips
    public let committedThisStreet: Chips
    public let hasFolded: Bool
    public let isAllIn: Bool
    public init(_ seat: SeatState) {
        id = seat.id
        stack = seat.stack
        committedThisStreet = seat.committedThisStreet
        hasFolded = seat.hasFolded
        isAllIn = seat.isAllIn
    }
}

public struct SpectatorObservation: Equatable, Sendable {
    public let communityCards: [Card]
    public let publicSeats: [PublicSeat]
    public let events: [GameEvent]
    public init(state: HoldemState) {
        communityCards = state.communityCards
        publicSeats = state.seats.map(PublicSeat.init)
        events = state.actionHistory.map { .actionApplied(seat: $0.seat, action: $0.action) }
    }
}

public struct CompletedHandRecord: Codable, Equatable, Sendable {
    public let holeCardsBySeat: [SeatID: [Card]]
    public let communityCards: [Card]
    public let actions: [RecordedAction]
    public let pots: [Pot]
    public let awards: [SeatID: Chips]
    public init(state: HoldemState) throws {
        guard state.street == .complete else { throw PokerRuleError.illegalAction("hand not complete") }
        holeCardsBySeat = Dictionary(uniqueKeysWithValues: state.seats.filter { !$0.holeCards.isEmpty }.map { ($0.id, $0.holeCards) })
        communityCards = state.communityCards
        actions = state.actionHistory
        pots = state.settledPots
        awards = state.awards
    }
}
```

在 `project.yml` 顶层加入本地包，并把依赖合并进现有目标；本任务不改现有 SwiftUI 牌桌行为：

```yaml
packages:
  PokerCore:
    path: Packages/PokerCore

targets:
  RiverClub:
    dependencies:
      - package: PokerCore
  RiverClubTests:
    dependencies:
      - target: RiverClub
      - package: PokerCore
```

保留 `project.yml` 中现有的应用类型、sources、iPhone-only 和左右横屏设置，不能用上述片段覆盖其他键。

- [ ] **步骤 4：运行包测试与应用编译检查**

运行：

```bash
swift test --package-path Packages/PokerCore
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing -project RiverClub.xcodeproj -scheme RiverClub -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

预期：`swift test` 全部通过；XcodeGen 成功。若本机仍因 iOS 26.5/CoreSimulator 版本不匹配导致 `xcodebuild` 无法选择目标，必须记录真实 exit code，不得把环境失败描述为编译通过。

- [ ] **步骤 5：提交任务 9**

```bash
git add Packages/PokerCore project.yml
git commit -m "feat: expose safe PokerCore snapshots"
```

## 完成标准

- `swift test --package-path Packages/PokerCore` 全部通过。
- 2–9 人完整牌局均可使用固定种子确定性重放。
- 牌型、行动顺序、最小加注、短码全下、任意边池、平分和奇数筹码均有直接测试。
- 500 个种子随机合法牌局满足牌张唯一、非负筹码、赢家资格和筹码守恒。
- `PlayerObservation` 从类型上不暴露对手底牌和牌堆。
- 只有 `.complete` 状态能生成包含所有已发底牌（包括弃牌者）的 `CompletedHandRecord`。
- 规则包可被后续普通桌、锦标赛、存档和机器人计划直接依赖。

## 后续计划边界

完成本计划后再编写和执行：

1. 本地会话与智能机器人计划：普通桌、单桌锦标赛、筹码账本、永久存档、三档难度与四种决策模型。
2. SwiftUI 功能接入计划：协调器、玩家倒计时、机器人设置、牌局记录查看器、恢复流程和端到端 UI 验收。
