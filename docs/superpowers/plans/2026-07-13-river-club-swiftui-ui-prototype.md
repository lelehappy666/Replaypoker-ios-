# River Club SwiftUI UI Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable, landscape-only SwiftUI prototype of the seven approved River Club screens using local fixtures and deterministic UI state.

**Architecture:** Use a small feature-oriented SwiftUI app with one observable `AppSession`, protocol-based local repositories, and reusable design-system components. The prototype contains no poker rules engine or networking; buttons drive deterministic local state so every approved flow can be reviewed and tested independently.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest/XCUITest, Xcode 26, iOS 18+, XcodeGen 2.44+ as a development-only project generator.

## Global Constraints

- Target iPhone 16 Pro Max and support landscape left/right only.
- Deployment target is iOS 18.0.
- Use only entertainment chips with no cash value, withdrawal, exchange, or real-currency symbols.
- First release supports No-Limit Texas Hold’em only.
- Show exactly nine seats at a full table: eight opponents and the local player.
- Keep the local player avatar circular and prevent horizontal compression.
- Place the pot below the community cards and the chip stack below the pot.
- Respect the Dynamic Island and Home Indicator safe areas.
- Use original River Club names and assets; do not copy Replay Poker trademarks, logos, illustrations, or proprietary visual assets.
- Runtime dependencies must remain Apple-native; XcodeGen is development-only.
- This plan implements UI behavior with mock data, not a poker rules engine, real-time multiplayer, authentication server, or chip-economy backend.

---

## Planned File Structure

```text
project.yml                                  XcodeGen project definition
RiverClub/App/RiverClubApp.swift             Application entry and orientation policy
RiverClub/App/AppRootView.swift              Session routing and root composition
RiverClub/App/AppSession.swift               Observable navigation/session state
RiverClub/DesignSystem/Theme.swift           Colors, spacing, type, shadows
RiverClub/DesignSystem/AppSidebar.swift      Shared landscape navigation
RiverClub/DesignSystem/ChipBalancePill.swift Shared virtual-chip display
RiverClub/Models/PokerModels.swift           UI domain models
RiverClub/Services/PokerRepository.swift     Data contract
RiverClub/Services/MockPokerRepository.swift Deterministic fixture data
RiverClub/Features/Auth/LoginView.swift       Login screen
RiverClub/Features/Lobby/LobbyView.swift      Featured and quick-join lobby
RiverClub/Features/Lobby/TableListView.swift Filterable table list
RiverClub/Features/Lobby/BuyInSheet.swift     Buy-in confirmation
RiverClub/Features/Table/PokerTableView.swift Nine-seat poker table
RiverClub/Features/Table/PokerSeatView.swift Reusable seat presentation
RiverClub/Features/Table/BetControlBar.swift Bet presets and slider
RiverClub/Features/Tournaments/TournamentsView.swift Tournament cards
RiverClub/Features/Profile/ProfileView.swift Profile and settings links
RiverClub/Features/Shared/LoadableContent.swift Loading/empty/offline/error states
RiverClubTests/AppSessionTests.swift          Navigation/session unit tests
RiverClubTests/MockPokerRepositoryTests.swift Fixture and seat-count tests
RiverClubTests/BuyInTests.swift               Buy-in validation tests
RiverClubUITests/CoreFlowUITests.swift        End-to-end UI flow
RiverClubUITests/LandscapeLayoutUITests.swift Landscape and accessibility checks
```

## Task 1: Bootstrap the Landscape SwiftUI App

**Files:**
- Create: `project.yml`
- Create: `RiverClub/App/RiverClubApp.swift`
- Create: `RiverClub/App/AppRootView.swift`
- Create: `RiverClub/App/AppSession.swift`
- Create: `RiverClubTests/AppSessionTests.swift`

**Interfaces:**
- Produces: `enum AppRoute`, `@Observable final class AppSession`, and `AppRootView`.
- Consumes: no earlier task.

- [ ] **Step 1: Confirm implementation prerequisites**

Run:

```bash
xcode-select -p
xcodebuild -version
xcodegen --version
```

Expected: the active developer directory points inside `Xcode.app`, Xcode reports version 26, and XcodeGen reports 2.44 or newer. If Xcode is installed but not selected, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` after user approval.

- [ ] **Step 2: Write the failing session test**

Create `RiverClubTests/AppSessionTests.swift`:

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

- [ ] **Step 3: Create the project definition and minimal app**

Create `project.yml`:

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

Create `RiverClub/App/AppSession.swift`:

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

Create `RiverClub/App/RiverClubApp.swift`:

```swift
import SwiftUI

@main struct RiverClubApp: App {
    @State private var session = AppSession()
    var body: some Scene { WindowGroup { AppRootView(session: session) } }
}
```

Create `RiverClub/App/AppRootView.swift`:

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

- [ ] **Step 4: Generate the project and run the test**

Run:

```bash
xcodegen generate
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:RiverClubTests/AppSessionTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit the bootstrap**

```bash
git add project.yml RiverClub RiverClubTests
git commit -m "feat: bootstrap River Club landscape app"
```

## Task 2: Add the Design System and Shared Shell

**Files:**
- Create: `RiverClub/DesignSystem/Theme.swift`
- Create: `RiverClub/DesignSystem/AppSidebar.swift`
- Create: `RiverClub/DesignSystem/ChipBalancePill.swift`
- Modify: `RiverClub/App/AppRootView.swift`
- Test: `RiverClubTests/AppSessionTests.swift`

**Interfaces:**
- Consumes: `AppSession.open(_:)`, `AppRoute`.
- Produces: `RCTheme`, `AppSidebar(selection:onSelect:)`, and `ChipBalancePill(balance:)`.

- [ ] **Step 1: Add a failing sidebar-route contract test**

Append to `AppSessionTests`:

```swift
func testSidebarRoutesAreStable() {
    XCTAssertEqual(AppRoute.sidebarRoutes, [.lobby, .tournaments, .tables, .profile])
}
```

- [ ] **Step 2: Run the focused test**

Run the Task 1 `xcodebuild test` command with `-only-testing:RiverClubTests/AppSessionTests/testSidebarRoutesAreStable`.

Expected: FAIL because `AppRoute.sidebarRoutes` does not exist.

- [ ] **Step 3: Implement theme tokens and shared components**

Create `Theme.swift`:

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

Add the shared navigation contract to `AppRoute`:

```swift
extension AppRoute {
    static let sidebarRoutes: [AppRoute] = [.lobby, .tournaments, .tables, .profile]
}
```

Create `AppSidebar.swift` with four labeled buttons for `.lobby`, `.tournaments`, `.tables`, and `.profile`; apply `.accessibilityIdentifier("sidebar.<route>")` to each button and call `onSelect(route)`.

Create `ChipBalancePill.swift`:

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

Modify `AppRootView` so authenticated routes render an `HStack(spacing: 0)` containing `AppSidebar` and the current feature placeholder, while `.table` renders without the sidebar.

- [ ] **Step 4: Run unit tests**

Run:

```bash
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:RiverClubTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add RiverClub/DesignSystem RiverClub/App RiverClubTests
git commit -m "feat: add River Club design system shell"
```

## Task 3: Define UI Models and Deterministic Fixtures

**Files:**
- Create: `RiverClub/Models/PokerModels.swift`
- Create: `RiverClub/Services/PokerRepository.swift`
- Create: `RiverClub/Services/MockPokerRepository.swift`
- Create: `RiverClubTests/MockPokerRepositoryTests.swift`

**Interfaces:**
- Produces: `PokerTableSummary`, `PokerSeat`, `TournamentSummary`, `ProfileSummary`, `PokerRepository`, and `MockPokerRepository`.
- Consumes: no view code.

- [ ] **Step 1: Write fixture contract tests**

Create `MockPokerRepositoryTests.swift` verifying `tables()` returns at least three tables, `featuredTable()` has an open seat, `seats()` returns exactly nine unique positions with exactly one `isLocalPlayer`, and no formatted value contains `¥`, `$`, `€`, or `£`.

- [ ] **Step 2: Run tests and confirm missing-type failures**

Run `xcodebuild test` limited to `RiverClubTests/MockPokerRepositoryTests`.

Expected: FAIL because the repository types do not exist.

- [ ] **Step 3: Implement models and repository**

Define these exact signatures in `PokerModels.swift`:

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

Define `PokerRepository` with these exact signatures:

```swift
protocol PokerRepository: Sendable {
    func tables() async throws -> [PokerTableSummary]
    func featuredTable() async throws -> PokerTableSummary
    func seats() async throws -> [PokerSeat]
    func tournaments() async throws -> [TournamentSummary]
    func profile() async throws -> ProfileSummary
}
```

Implement `MockPokerRepository` with the approved names 翡翠湾、金色海岸、午夜俱乐部 and nine deterministic seats. Use fixed UUID literals so UI tests remain stable.

- [ ] **Step 4: Run repository tests**

Expected: all fixture contract tests pass.

- [ ] **Step 5: Commit**

```bash
git add RiverClub/Models RiverClub/Services RiverClubTests/MockPokerRepositoryTests.swift
git commit -m "feat: add deterministic poker UI fixtures"
```

## Task 4: Implement Login, Lobby, Table List, and Buy-In Flow

**Files:**
- Create: `RiverClub/Features/Auth/LoginView.swift`
- Create: `RiverClub/Features/Lobby/LobbyView.swift`
- Create: `RiverClub/Features/Lobby/TableListView.swift`
- Create: `RiverClub/Features/Lobby/BuyInSheet.swift`
- Create: `RiverClubTests/BuyInTests.swift`
- Modify: `RiverClub/App/AppRootView.swift`

**Interfaces:**
- Consumes: `AppSession`, `PokerRepository`, `PokerTableSummary`, shared design system.
- Produces: `BuyInState`, `LoginView`, `LobbyView`, `TableListView`, and `BuyInSheet`.

- [ ] **Step 1: Write buy-in validation tests**

Create `BuyInTests.swift`:

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

- [ ] **Step 2: Run tests and confirm failure**

Expected: FAIL because `BuyInState` is undefined.

- [ ] **Step 3: Implement the flow**

Implement `BuyInState` in `BuyInSheet.swift` with `minimum`, `maximum`, `balance`, mutable `amount`, `autoTopUp`, `canConfirm`, and `normalize()` clamping to `min(maximum, balance)`.

Implement the four approved screens using `NavigationStack`, `safeAreaPadding`, reusable rows, and accessibility identifiers: `login.apple`, `login.guest`, `lobby.quickJoin`, `lobby.allTables`, `tableRow.<uuid>`, `buyIn.slider`, and `buyIn.confirm`.

Wire guest login to `.lobby`, “查看全部” to `.tables`, row selection to the sheet, and successful confirmation to `.table`. Keep balance insufficient errors inside the sheet.

- [ ] **Step 4: Run unit tests and build**

Run:

```bash
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:RiverClubTests
xcodebuild build -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

Expected: tests pass and build succeeds.

- [ ] **Step 5: Commit**

```bash
git add RiverClub/Features/Auth RiverClub/Features/Lobby RiverClub/App RiverClubTests/BuyInTests.swift
git commit -m "feat: implement lobby and buy-in prototype flow"
```

## Task 5: Implement the Nine-Seat Poker Table

**Files:**
- Create: `RiverClub/Features/Table/PokerSeatView.swift`
- Create: `RiverClub/Features/Table/BetControlBar.swift`
- Create: `RiverClub/Features/Table/PokerTableView.swift`
- Create: `RiverClubTests/PokerTableLayoutTests.swift`
- Modify: `RiverClub/App/AppRootView.swift`

**Interfaces:**
- Consumes: `[PokerSeat]`, `AppSession`, `RCTheme`.
- Produces: `PokerTableLayout.positions(for:)`, `PokerSeatView`, `BetControlBar`, `PokerTableView`.

- [ ] **Step 1: Write layout invariant tests**

Test that `PokerTableLayout.positions(for: CGSize(width: 956, height: 440))` returns nine distinct normalized points, local-player index 8 is below the table center, all points are inside `0...1`, and the eight opponent frames do not intersect the local-player frame.

- [ ] **Step 2: Run tests and confirm failure**

Expected: FAIL because `PokerTableLayout` is undefined.

- [ ] **Step 3: Implement layout and table components**

Use normalized seat centers:

```swift
static let normalizedCenters: [CGPoint] = [
    .init(x: 0.25, y: 0.16), .init(x: 0.50, y: 0.10), .init(x: 0.75, y: 0.16),
    .init(x: 0.88, y: 0.34), .init(x: 0.86, y: 0.62), .init(x: 0.18, y: 0.68),
    .init(x: 0.12, y: 0.48), .init(x: 0.14, y: 0.27), .init(x: 0.50, y: 0.86)
]
```

In `PokerSeatView`, render the avatar with `.frame(width: 42, height: 42)`, `.clipShape(Circle())`, and `.fixedSize()` so it never compresses. Use `ViewThatFits` for long nicknames.

In `PokerTableView`, place community cards at center, pot below them, and chips below the pot. Place fold/call/raise controls in a bottom-trailing safe-area inset and chat controls bottom-leading. Add `table.seat.0` through `table.seat.8`, `table.pot`, `action.fold`, `action.call`, and `action.raise` identifiers.

- [ ] **Step 4: Run layout tests and build**

Expected: nine-seat invariants pass and the app builds for iPhone 16 Pro Max.

- [ ] **Step 5: Commit**

```bash
git add RiverClub/Features/Table RiverClub/App RiverClubTests/PokerTableLayoutTests.swift
git commit -m "feat: add accessible nine-seat poker table UI"
```

## Task 6: Implement Tournaments and Profile

**Files:**
- Create: `RiverClub/Features/Tournaments/TournamentsView.swift`
- Create: `RiverClub/Features/Profile/ProfileView.swift`
- Modify: `RiverClub/App/AppRootView.swift`
- Modify: `RiverClubTests/MockPokerRepositoryTests.swift`

**Interfaces:**
- Consumes: `TournamentSummary`, `ProfileSummary`, `PokerRepository`.
- Produces: `TournamentTab.filtered(_:)`, approved tournament cards, and profile summary/settings links.

- [ ] **Step 1: Write tournament filtering tests**

Create tests asserting `.upcoming.filtered(fixtures)` excludes past start times, `.registered` includes only registered identifiers supplied to the filter, and fixture profile VPIP is within `0...1`.

- [ ] **Step 2: Run the focused repository tests**

Expected: FAIL because `TournamentTab.filtered(_:)` does not exist.

- [ ] **Step 3: Implement both screens**

Define `TournamentTab` as `upcoming`, `registered`, `active`, and `finished`, with `filtered(_:now:registeredIDs:) -> [TournamentSummary]`. Build the matching tabs; each card shows start time, registration count, prize chips, and a free/register state. Build profile identity, level progress, three approved statistics, and links for hand history, achievements, account/security, and sound/haptics.

Add identifiers `tournaments.tab.<state>`, `tournament.<uuid>`, `profile.nickname`, and `profile.settings`.

- [ ] **Step 4: Run tests and build**

Expected: unit tests pass and all root routes compile.

- [ ] **Step 5: Commit**

```bash
git add RiverClub/Features/Tournaments RiverClub/Features/Profile RiverClub/App RiverClubTests
git commit -m "feat: add tournament and profile screens"
```

## Task 7: Add Loadable, Offline, Empty, and Failure States

**Files:**
- Create: `RiverClub/Features/Shared/LoadableContent.swift`
- Modify: `RiverClub/Features/Lobby/LobbyView.swift`
- Modify: `RiverClub/Features/Lobby/TableListView.swift`
- Modify: `RiverClub/Features/Tournaments/TournamentsView.swift`
- Create: `RiverClubTests/LoadableStateTests.swift`

**Interfaces:**
- Produces: `enum LoadableState<Value>` and `LoadableContent`.
- Consumes: feature content views and repository errors.

- [ ] **Step 1: Write state-mapping tests**

Test deterministic mappings for loading, loaded-empty, loaded-content, offline, and failed states. Verify retry is offered for offline/failed, clear-filter is offered only for filtered empty results, and sidebar state remains unchanged.

- [ ] **Step 2: Run tests and confirm failure**

Expected: FAIL because `LoadableState` does not exist.

- [ ] **Step 3: Implement explicit state views**

Define:

```swift
enum LoadableState<Value> {
    case loading
    case loaded(Value)
    case offline(cached: Value?)
    case failed(message: String)
}
```

Implement skeleton rows for loading, a clear-filter action for filtered empty lists, a nonmodal offline banner when cached data exists, and an inline retry action for uncached failure. Never replace the full root view with a transient toast.

- [ ] **Step 4: Run state tests and full unit suite**

Expected: all unit tests pass.

- [ ] **Step 5: Commit**

```bash
git add RiverClub/Features RiverClubTests/LoadableStateTests.swift
git commit -m "feat: add resilient UI loading and error states"
```

## Task 8: Add End-to-End UI Verification

**Files:**
- Create: `RiverClubUITests/CoreFlowUITests.swift`
- Create: `RiverClubUITests/LandscapeLayoutUITests.swift`

**Interfaces:**
- Consumes: accessibility identifiers from Tasks 2–7.
- Produces: automated acceptance evidence for the approved UI flow and layout invariants.

- [ ] **Step 1: Write the core-flow UI test**

Launch with `-uiTesting`, tap `login.guest`, verify the lobby, open all tables, select the first row, set buy-in, confirm, and assert `table.seat.0...8`, `table.pot`, and all three action buttons exist.

- [ ] **Step 2: Write landscape and compliance UI tests**

Assert the window width exceeds height, all nine seat frames are hittable or visible and do not intersect the local-player frame, the local avatar width equals height within one point, and app static text contains none of `¥`, `$`, `€`, or `£`.

- [ ] **Step 3: Run UI tests on iPhone 16 Pro Max**

Run:

```bash
xcodebuild test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:RiverClubUITests
```

Expected: `** TEST SUCCEEDED **` with the full flow completing in landscape.

- [ ] **Step 4: Run the complete verification suite**

Run:

```bash
xcodebuild clean test -project RiverClub.xcodeproj -scheme RiverClub -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

Expected: clean build and all unit/UI tests pass.

- [ ] **Step 5: Commit verification**

```bash
git add RiverClubUITests
git commit -m "test: verify River Club core landscape flow"
```

## Follow-Up Plans After UI Prototype Approval

The following independent subsystems require separate specifications and implementation plans:

1. Texas Hold’em rules engine: deck, dealing, betting rounds, legal actions, side pots, showdown, hand evaluation, deterministic simulations, and property tests.
2. Real-time multiplayer platform: table matchmaking, authoritative game server, reconnection, action timers, anti-cheat boundaries, observability, and load testing.
3. Accounts and entertainment-chip service: Sign in with Apple server validation, profiles, chip ledger, daily grants, idempotency, moderation, privacy, and account deletion.
4. Client/server integration and release: API contracts, WebSocket protocol, localization, analytics consent, App Store metadata, TestFlight, and production rollout.
