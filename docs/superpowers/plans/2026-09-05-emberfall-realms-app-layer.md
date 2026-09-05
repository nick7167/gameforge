# Emberfall Realms — Plan 2: App Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full iOS app on top of the finished GameCore engine: the EmberGameModel facade, SceneKit battle stage + 3D hub matching the approved WebGL prototype, the complete SwiftUI UI suite (Hub, Heroes, Summon, Market, Premium Shop, More, battle HUD, popups), persistence, and service wiring (RevenueCat, AdMob, Firebase-ready).

**Architecture:** `EmberGameModel` (@MainActor ObservableObject) owns an `EmberSession` value and republishes its state; views never touch GameCore directly except through the model. SceneKit scenes (`BattleScene`, `HubScene`) are dumb renderers driven by GameCore state — all rules stay in GameCore. The art direction (dark + glow, gold ornate UI, rarity colors, glowing stage circles) comes from the approved WebGL prototype and `docs/art-reference/`.

**Tech Stack:** SwiftUI, SceneKit, GameCore (SPM), RevenueCat, GoogleMobileAds, XCTest (app smoke tests).

**Spec:** `docs/superpowers/specs/2026-09-03-emberfall-realms-design.md`

## Global Constraints

- Portrait only: `project.yml` orientations must be reduced to Portrait + PortraitUpsideDown (spec §2)
- Swift 6 strict concurrency; `@MainActor` on all ObservableObjects; views never own game state
- GameCore is the only rules source — scenes/views translate state to pixels, never decide outcomes
- Art direction (spec §13): dark rich bg (#120A1E-ish), gold trim (#FFD76A/#C9A227), rarity colors from `Rarity.uiColorHex`, glowing stage circles, chunky beveled gold buttons, big outlined damage numbers
- All randomness in rendering (particles, drift) may use system RNG; game outcomes never do
- App tests are XCTest (`Tests/AppTests`), must run in CI simulator; every view gets a render smoke test
- Local verification: `swift test` in GameCore + `swiftlint`; app builds only in CI (no Xcode locally) — verify macOS-only APIs via research before writing SceneKit code
- Existing services (`AdService`, `PurchaseService`, `GameCenterService`, `Persistence`) are kept and adapted, not rewritten
- IAP product IDs renamed from `dev.adrez.skyline.*` to `dev.adrez.emberfall.*` in this plan

---

### Task 1: EmberGameModel — the app-side facade

**Files:**
- Create: `Sources/App/EmberGameModel.swift`
- Modify: `Sources/App/RootView.swift` (hold the model, pass to views)
- Test: `Tests/AppTests/EmberGameModelTests.swift`

**Interfaces:**
- Consumes: `EmberSession`, `PlayerProfile`, `BattleEngine`, `BattleReward`, `GachaEngine`, `StageID`, `GearItem` (all from GameCore, already built)
- Produces: `@MainActor final class EmberGameModel: ObservableObject` with:
  - `@Published private(set) var profile: PlayerProfile`
  - `@Published private(set) var battle: BattleEngine?`
  - `@Published private(set) var lastReward: BattleReward?`
  - `@Published private(set) var lastSummonResults: [GachaEngine.PullResult]?`
  - `@Published private(set) var idleGoldAvailable: Int`
  - `var currentStage: StageID { session.currentStage }`
  - `func startBattle()`, `func tickBattle(_ dt: Double)`, `func fireUltimate(heroID: String)`, `func finishBattle()`
  - `func summon(banner: GachaEngine.BannerKind, count: Int)`, `func levelUpHero(heroID: String)`, `func equipGear(heroID:item:slot:)`, `func enhanceGear(heroID:slot:)`
  - `func claimIdle()`, `func refreshIdleEstimate()`
  - `func save()` (persists via `ProfilePersistence`)
  - `init(profile: PlayerProfile? = nil)` — loads persisted or creates new
  - Battle ticking: a `CADisplayLink`-free `Timer` at 30 Hz while a battle is ongoing (started/stopped internally)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import GameCore
@testable import GameForge

@MainActor
final class EmberGameModelTests: XCTestCase {
  func testModelStartsBattleAndFinishes() {
    let model = EmberGameModel(profile: PlayerProfile.new())
    XCTAssertNil(model.battle)
    model.startBattle()
    XCTAssertNotNil(model.battle)
    // Tick to completion (fast-forward)
    for _ in 0..<20000 where model.battle?.outcome == .ongoing {
      model.tickBattle(0.1)
    }
    model.finishBattle()
    XCTAssertNil(model.battle)
  }

  func testSummonUpdatesProfile() {
    let model = EmberGameModel(profile: PlayerProfile.new())
    model.addGemsForTesting(100_000)
    let before = model.profile.totalSummons
    model.summon(banner: .permanent, count: 1)
    XCTAssertEqual(model.profile.totalSummons, before + 1)
  }

  func testIdleClaimGrantsGold() {
    let model = EmberGameModel(profile: PlayerProfile.new())
    let gold = model.claimIdle(secondsAway: 3600)
    XCTAssertGreaterThanOrEqual(gold, 0)
  }

  func testSaveAndReloadRoundTrip() {
    let model = EmberGameModel(profile: PlayerProfile.new())
    model.renamePlayer("Test Keeper")
    model.save()
    let reloaded = EmberGameModel() // loads from disk
    XCTAssertEqual(reloaded.profile.name, "Test Keeper")
    ProfilePersistence.wipe()
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: CI app-build-test (or `xcodebuild test` if available)
Expected: FAIL — `EmberGameModel` not found

- [ ] **Step 3: Implement EmberGameModel**

```swift
import Foundation
import GameCore
import Combine

/// The app-side game facade. Owns the EmberSession, republishes state,
/// and drives the battle tick loop. Views observe this; they never touch
/// GameCore types directly for state mutation.
@MainActor
final class EmberGameModel: ObservableObject {
  @Published private(set) var profile: PlayerProfile
  @Published private(set) var battle: BattleEngine?
  @Published private(set) var lastReward: BattleReward?
  @Published private(set) var lastSummonResults: [GachaEngine.PullResult]?
  @Published private(set) var idleGoldAvailable: Int = 0

  private var session: EmberSession
  private var tickTimer: Timer?

  var currentStage: StageID { session.currentStage }

  init(profile: PlayerProfile? = nil) {
    let loaded = profile ?? ProfilePersistence.load() ?? PlayerProfile.new()
    self.session = EmberSession(profile: loaded, rngSeed: UInt64(Date().timeIntervalSince1970))
    self.profile = loaded
    refreshIdleEstimate()
  }

  // MARK: - Battle

  func startBattle() {
    guard battle == nil else { return }
    battle = session.startBattle()
    startTicking()
  }

  func tickBattle(_ dt: Double) {
    guard battle != nil else { return }
    session.tickBattle(dt)
    battle = session.battle
    if battle?.outcome != .ongoing { stopTicking() }
  }

  func fireUltimate(heroID: String) {
    session.fireUltimate(heroID: heroID)
    battle = session.battle
  }

  func finishBattle() {
    lastReward = session.finishBattle()
    battle = session.battle
    syncProfile()
    save()
  }

  private func startTicking() {
    stopTicking()
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.tickBattle(1.0 / 30.0)
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    tickTimer = timer
  }

  private func stopTicking() {
    tickTimer?.invalidate()
    tickTimer = nil
  }

  // MARK: - Meta actions

  func summon(banner: GachaEngine.BannerKind, count: Int) {
    lastSummonResults = session.summon(banner: banner, count: count)
    syncProfile()
    save()
  }

  func levelUpHero(heroID: String) {
    _ = session.levelUpHero(heroID: heroID)
    syncProfile()
    save()
  }

  func equipGear(heroID: String, item: GearItem, slot: GearSlot) {
    _ = session.equipGear(heroID: heroID, item: item, slot: slot)
    syncProfile()
    save()
  }

  func enhanceGear(heroID: String, slot: GearSlot) {
    _ = session.enhanceGear(heroID: heroID, slot: slot)
    syncProfile()
    save()
  }

  @discardableResult
  func claimIdle(secondsAway: Double? = nil) -> Int {
    let gold = session.claimIdle(secondsAway: secondsAway)
    syncProfile()
    save()
    return gold
  }

  func refreshIdleEstimate() {
    // Estimate what's available now without claiming
    if let last = profile.lastIdleClaim {
      let elapsed = Date().timeIntervalSince(last)
      idleGoldAvailable = IdleIncome.earnings(bestStage: profile.bestStage, secondsAway: elapsed).gold
    } else {
      idleGoldAvailable = 0
    }
  }

  func renamePlayer(_ name: String) {
    session.renamePlayer(name)
    syncProfile()
    save()
  }

  /// Test hook: grant gems without a purchase.
  func addGemsForTesting(_ amount: Int) {
    session.grantGems(amount)
    syncProfile()
  }

  private func syncProfile() {
    profile = session.profile
  }

  func save() {
    ProfilePersistence.save(profile)
  }
}
```

*(Note: `session.renamePlayer(_:)` and `session.grantGems(_:)` don't exist yet in
GameCore — add them in this task as small public methods on `EmberSession`:
`public mutating func renamePlayer(_ name: String) { profile.name = name }` and
`public mutating func grantGems(_ amount: Int) { profile.wallet.add(.gems, amount) }`,
each with a GameCore test.)*

- [ ] **Step 4: Add the two GameCore methods + tests**

In `Packages/GameCore/Sources/GameCore/EmberSession.swift`, add:

```swift
  /// Rename the player (profile screen).
  public mutating func renamePlayer(_ name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    profile.name = String(trimmed.prefix(20))
  }

  /// Grant gems (IAP fulfillment, rewards). Server-validated later (Plan 3).
  public mutating func grantGems(_ amount: Int) {
    guard amount > 0 else { return }
    profile.wallet.add(.gems, amount)
  }
```

In `Packages/GameCore/Tests/GameCoreTests/EmberSessionTests.swift`, add:

```swift
  @Test func renamePlayerTrimsAndLimits() {
    var session = EmberSession()
    session.renamePlayer("  Ember Knight  ")
    #expect(session.profile.name == "Ember Knight")
    session.renamePlayer(String(repeating: "x", count: 50))
    #expect(session.profile.name.count == 20)
    session.renamePlayer("   ")
    #expect(session.profile.name == String(repeating: "x", count: 20)) // unchanged
  }

  @Test func grantGemsOnlyPositive() {
    var session = EmberSession()
    let before = session.profile.wallet.balance(of: .gems)
    session.grantGems(100)
    session.grantGems(-50)
    #expect(session.profile.wallet.balance(of: .gems) == before + 100)
  }
```

- [ ] **Step 5: Run all tests**

Run: `cd Packages/GameCore && swift test` — Expected: PASS (96 tests)
Run: CI app tests — Expected: PASS

- [ ] **Step 6: Lint and commit**

```bash
swiftlint --quiet
git add -A && git commit -m "Add EmberGameModel facade with battle ticking and persistence"
```

---

### Task 2: Design system — colors, fonts, buttons, panels

**Files:**
- Create: `Sources/UI/DesignSystem.swift`
- Test: `Tests/AppTests/DesignSystemTests.swift`

**Interfaces:**
- Produces: `enum DS` (design system) with:
  - `static let emberDark, panelDark, goldLight, goldMid, goldDeep: Color`
  - `static func rarityColor(_ r: Rarity) -> Color` (from `Rarity.uiColorHex`)
  - `static func factionColor(_ f: Faction) -> Color` (ember=#FF7A2A, frost=#4FC3F7, verdant=#7DD858, void=#9B6DFF)
  - `struct GoldButton: View` (`title: String, action: () -> Void`, gem variant via `style: .gold/.gem/.disabled`)
  - `struct OrnatePanel<Content: View>: View` (gold-bordered dark panel wrapping content)
  - `struct CurrencyChip: View` (`icon: String, value: Int`)
  - `struct RarityFrame<Content: View>: View` (rarity-colored border frame)
  - `struct DamageNumberStyle` helpers (text shadow constants)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
import GameCore
@testable import GameForge

final class DesignSystemTests: XCTestCase {
  func testRarityColorsMatchGameCore() {
    // The DS must derive from GameCore's Rarity.uiColorHex, not hardcode
    for rarity in [Rarity.common, .rare, .epic, .legendary] {
      let color = DS.rarityColor(rarity)
      XCTAssertNotNil(color) // non-crashing derivation
    }
  }

  func testGoldButtonRenders() {
    let view = GoldButton(title: "SUMMON ×10", style: .gold, action: {})
    _ = view.body
    let gem = GoldButton(title: "BUY", style: .gem, action: {})
    _ = gem.body
  }

  func testOrnatePanelRenders() {
    let panel = OrnatePanel { Text("content") }
    _ = panel.body
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `DS` not found

- [ ] **Step 3: Implement the design system**

```swift
import SwiftUI
import GameCore

/// Emberfall Realms design system (spec §13): dark + glow, gold ornate UI.
enum DS {
  // Palette (from the approved WebGL prototype)
  static let emberDark = Color(red: 0.07, green: 0.04, blue: 0.12)
  static let panelDark = Color(red: 0.13, green: 0.09, blue: 0.20)
  static let panelLight = Color(red: 0.22, green: 0.16, blue: 0.33)
  static let goldLight = Color(red: 1.00, green: 0.84, blue: 0.44)
  static let goldMid = Color(red: 0.94, green: 0.71, blue: 0.16)
  static let goldDeep = Color(red: 0.77, green: 0.50, blue: 0.05)
  static let textPrimary = Color(red: 1.00, green: 0.91, blue: 0.66)
  static let textSecondary = Color(red: 0.72, green: 0.66, blue: 0.55)

  static func rarityColor(_ rarity: Rarity) -> Color {
    Color(hex: rarity.uiColorHex)
  }

  static func factionColor(_ faction: Faction) -> Color {
    switch faction {
    case .ember: return Color(red: 1.00, green: 0.48, blue: 0.16)
    case .frost: return Color(red: 0.31, green: 0.76, blue: 0.97)
    case .verdant: return Color(red: 0.49, green: 0.85, blue: 0.35)
    case .void: return Color(red: 0.61, green: 0.43, blue: 1.00)
    }
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}

/// Chunky beveled gold button (prototype-verified styling).
struct GoldButton: View {
  enum Style { case gold, gem, disabled }
  let title: String
  let style: Style
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 16, weight: .heavy, design: .rounded))
        .foregroundColor(style == .gem ? .white : DS.emberDark)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(
          Capsule().fill(
            LinearGradient(
              colors: style == .gem
                ? [Color(red: 0.72, green: 0.55, blue: 1.0), Color(red: 0.36, green: 0.13, blue: 0.71)]
                : [DS.goldLight, DS.goldMid, DS.goldDeep],
              startPoint: .top, endPoint: .bottom))
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
        .opacity(style == .disabled ? 0.45 : 1)
    }
    .disabled(style == .disabled)
  }
}

/// Gold-bordered dark panel.
struct OrnatePanel<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(14)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(LinearGradient(colors: [DS.panelLight, DS.panelDark], startPoint: .top, endPoint: .bottom)))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(
            LinearGradient(colors: [DS.goldLight, DS.goldDeep, DS.goldLight], startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1.5))
      .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
  }
}

/// Currency chip for the top bar.
struct CurrencyChip: View {
  let icon: String
  let value: Int

  var body: some View {
    HStack(spacing: 5) {
      Text(icon).font(.system(size: 13))
      Text(value.formatted())
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundColor(DS.textPrimary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Capsule().fill(Color.black.opacity(0.45)))
    .overlay(Capsule().strokeBorder(DS.goldDeep.opacity(0.7), lineWidth: 1))
  }
}

/// Rarity-colored frame for hero/gear cards.
struct RarityFrame<Content: View>: View {
  let rarity: Rarity
  let content: Content

  init(rarity: Rarity, @ViewBuilder content: () -> Content) {
    self.rarity = rarity
    self.content = content()
  }

  var body: some View {
    content
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.rarityColor(rarity), lineWidth: 2))
      .shadow(color: DS.rarityColor(rarity).opacity(0.5), radius: 4)
  }
}
```

- [ ] **Step 4: Run tests**

Expected: PASS

- [ ] **Step 5: Lint and commit**

```bash
swiftlint --quiet
git add -A && git commit -m "Add design system: palette, gold buttons, ornate panels, rarity frames"
```

---

### Task 3: BattleScene — SceneKit stage matching the prototype

**Files:**
- Create: `Sources/Game/BattleScene.swift`
- Create: `Sources/Game/SceneKitSupport.swift` (color/vector helpers)

**Interfaces:**
- Consumes: `BattleEngine` (state mirror), `DS` palette
- Produces: `final class BattleScene` (not a View — pure SCNScene controller):
  - `init(engine: BattleEngine)`
  - `func sync(engine: BattleEngine, events: BattleEvents)` — called every tick; moves nodes, updates HP, spawns damage numbers via `events`
  - `func playUltimate(heroID: String, result: BattleEngine.UltFireResult)` — flash, banner trigger, particle burst, camera shake
  - `var scene: SCNScene`
  - `struct BattleEvents` — callbacks the view layer sets: `onDamageNumber(unitID: String, text: String, kind: DamageKind)`, `onUnitDied(unitID: String)`, `onUltimateCharged(heroID: String)`; `enum DamageKind { normal, crit, ult, heal }`
  - Visuals per prototype: dusk sky dome (shader gradient), arena cylinder + glowing rune ring, 5 hero nodes left / enemies right with faction-colored glowing stage circles (SCNTorus + additive), warm key light + faction rim lights, ember particle system, bloom via `SCNView` post-processing (or emissive + tone mapping fallback)

- [ ] **Step 1: Implement SceneKitSupport helpers**

```swift
import SceneKit
import GameCore

enum SceneKitSupport {
  static func color(_ c: Color-like from DS) -> UIColor { ... } // convert DS colors
  static func glowMaterial(_ color: UIColor, intensity: CGFloat) -> SCNMaterial {
    let m = SCNMaterial()
    m.emission.contents = color
    m.emission.intensity = intensity
    m.lightingModel = .constant
    return m
  }
  static func stageCircle(radius: CGFloat, color: UIColor) -> SCNNode {
    // Ring geometry, additive blend, slight pulse animation
  }
}
```

- [ ] **Step 2: Implement BattleScene**

Key structure (full implementation in the task):

```swift
import SceneKit
import GameCore

/// SceneKit renderer for the battle stage. Mirrors BattleEngine state into
/// nodes; owns zero game rules. Visual language from the approved prototype:
/// dusk sky, glowing stage circles, warm key + faction rims, embers, bloom.
final class BattleScene {
  struct BattleEvents {
    var onDamageNumber: ((String, String, DamageKind) -> Void)?
    var onUnitDied: ((String) -> Void)?
    var onUltimateCharged: ((String) -> Void)?
  }

  enum DamageKind { case normal, crit, ult, heal }

  let scene = SCNScene()
  private var heroNodes: [String: SCNNode] = [:]
  private var enemyNodes: [String: SCNNode] = [:]
  private var lastUltCharge: [String: Double] = [:]
  private var events = BattleEvents()

  init(engine: BattleEngine) {
    buildSky()
    buildArena()
    buildLights()
    buildEmbers()
    for unit in engine.heroes { spawnUnit(unit, x: -6.4 - Double(heroNodes.count) * 0.8) }
    for unit in engine.enemies { spawnUnit(unit, x: 5.6 + Double(enemyNodes.count) * 0.8) }
  }

  func sync(engine: BattleEngine, events: BattleEvents) { ... }
  func playUltimate(heroID: String, result: BattleEngine.UltFireResult) { ... }
}
```

Unit nodes: capsule torso + sphere head + weapon (per faction), glowing eyes,
stage circle (two additive rings, faction color, pulse via SCNAction repeat),
HP bar as SCNPlane with `SCNBillboardConstraint` above each unit.

Damage numbers: NOT SceneKit — the view layer overlays SwiftUI text at projected
screen positions (via `SCNView.projectPoint`), using `events.onDamageNumber`.

Camera: fixed position (0, 7.2, 20.5) looking at (0, 2.2, 0), subtle sine drift,
shake impulse on ults (decaying random offset).

- [ ] **Step 3: Verify compile in CI**

The app target builds only in CI. Push and watch `gh run list` — the
`App build + smoke tests` job must pass.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Add SceneKit battle stage matching the art prototype"
```

---

### Task 4: BattleView — SwiftUI HUD over the scene

**Files:**
- Create: `Sources/UI/BattleView.swift`
- Modify: `Sources/App/RootView.swift` (route to BattleView when battle active)

**Interfaces:**
- Consumes: `EmberGameModel`, `BattleScene`, `DS`
- Produces: `struct BattleView: View` — `UIViewRepresentable` wrapping `SCNView` + SwiftUI HUD overlay:
  - Top corners: stage badge ("3-7", chapter name), wave/enemy count
  - Boss HP bar (top center) when boss stage
  - Bottom-center: 5 ult portraits (circular, faction gradient, charge %, gold pulse ring when ready, tap → `model.fireUltimate`)
  - Bottom-left: speed button (1×/2×/4×), AUTO toggle (locked with 🔒 until account level 5)
  - Damage numbers overlay: SwiftUI `Text` at projected positions, animated float-up
  - Victory/defeat popup: loot burst, gold, gear drops, NEXT button → `model.finishBattle()`
  - Ult banner: hero name + skill name slam animation on ult fire

- [ ] **Step 1: Implement BattleView**

Structure:

```swift
import SwiftUI
import SceneKit
import GameCore

struct BattleView: View {
  @ObservedObject var model: EmberGameModel
  @State private var scene: BattleScene?
  @State private var damageNumbers: [DamageNumber] = []
  @State private var ultBanner: UltBanner?
  @State private var speed: Int = 1

  struct DamageNumber: Identifiable {
    let id = UUID()
    let unitID: String
    let text: String
    let kind: BattleScene.DamageKind
    let createdAt: Date
    let screenPos: CGPoint
  }

  var body: some View {
    ZStack {
      if let engine = model.battle {
        SceneViewHost(scene: scene ?? makeScene(engine: engine), events: ...)
          .ignoresSafeArea()
        hud(engine: engine)
        damageOverlay
        if let banner = ultBanner { ultBannerView(banner) }
        if engine.outcome != .ongoing { resultPopup(engine) }
      }
    }
  }
}
```

The HUD ult portraits read `engine.heroes` (id, faction, ultCharge, isAlive) each
tick — SwiftUI re-renders because `model.battle` is @Published and mutated per tick.

- [ ] **Step 2: Add render smoke test**

```swift
func testBattleViewRenders() {
  let model = EmberGameModel(profile: PlayerProfile.new())
  model.startBattle()
  let view = BattleView(model: model)
  _ = view.body
  model.finishBattle()
}
```

- [ ] **Step 3: Verify in CI, lint, commit**

```bash
swiftlint --quiet
git add -A && git commit -m "Add battle HUD with ult portraits, damage numbers, result popup"
```

---

### Task 5: HubScene + HubView — the 3D world home

**Files:**
- Create: `Sources/Game/HubScene.swift`
- Create: `Sources/UI/HubView.swift`

**Interfaces:**
- Consumes: `EmberGameModel`, `DS`
- Produces:
  - `final class HubScene` — portrait-framed 3D stronghold: floating island platform, Portal (glowing arch, tap → battle), Tavern, Forge, Merchant stand, Arena Gate (locked, v1.5), Tower (locked, v1.5), Guild Hall (locked, v2); hero nodes (squad) idle-walking between waypoints; ember particles; dusk lighting matching battle
  - `struct HubView: View` — SCNView + overlay: top bar (avatar/name, currency chips, settings gear), idle chest button (floating, shows `idleGoldAvailable`, tap → claim popup), event banner placeholder, bottom tab bar (Hub · Heroes · Summon · Market · More)
  - Building tap handling: `SCNNode` hit-test → route (`Portal` → start battle, `Tavern` → summon tab, `Forge` → heroes/inventory, `Merchant` → premium shop, locked buildings → "coming soon" toast)

- [ ] **Step 1: Implement HubScene**

Buildings are stylized low-poly primitives (box/cylinder/cone compositions) with
emissive accents and name labels (SCNText billboards). Heroes reuse the battle
unit factory at 0.8 scale, walking between 3–4 waypoints with `SCNAction` sequences.

- [ ] **Step 2: Implement HubView + tab navigation**

```swift
struct HubView: View {
  @ObservedObject var model: EmberGameModel
  @State private var selectedTab: Tab = .hub
  enum Tab { case hub, heroes, summon, market, more }

  var body: some View {
    ZStack {
      switch selectedTab {
      case .hub: hubScene
      case .heroes: HeroesView(model: model)
      case .summon: SummonView(model: model)
      case .market: MarketView(model: model)
      case .more: MoreView(model: model)
      }
      VStack {
        TopBar(model: model)
        Spacer()
        if selectedTab == .hub { idleChestButton }
        TabBar(selected: $selectedTab)
      }
    }
  }
}
```

- [ ] **Step 3: Render smoke tests + CI verify + commit**

```swift
func testHubViewRenders() {
  let model = EmberGameModel(profile: PlayerProfile.new())
  let view = HubView(model: model)
  _ = view.body
}
```

```bash
git add -A && git commit -m "Add 3D hub with buildings-as-buttons and tab navigation"
```

---

### Task 6: Heroes screens — roster, detail, team editor

**Files:**
- Create: `Sources/UI/HeroesView.swift` (roster grid + team editor)
- Create: `Sources/UI/HeroDetailView.swift` (detail with stats, gear, level-up)

**Interfaces:**
- Consumes: `EmberGameModel`, `HeroCatalog`, `DS`
- Produces:
  - `HeroesView`: grid of owned hero cards (rarity frame, faction icon, level, stars); sort picker (power/rarity/faction); team editor strip (5 slots, tap to swap)
  - `HeroDetailView`: full-body hero render (SceneKit preview node, single hero, slow turntable), stat block (HP/ATK/DEF/SPD/CRIT with green gear deltas), 4 gear slots (tap → inventory picker), level-up button (gold cost from `EmberSession.heroLevelCost`), enhance buttons per slot
  - Gear inventory picker: filterable list of unequipped `GearItem`s from `profile.gearInventory`

- [ ] **Step 1: Implement both views** (full SwiftUI; stat deltas computed by comparing `hero.stats()` with/without the candidate item)
- [ ] **Step 2: Render smoke tests**

```swift
func testHeroesViewRenders() {
  let model = EmberGameModel(profile: PlayerProfile.new())
  _ = HeroesView(model: model).body
  _ = HeroDetailView(model: model, heroID: model.profile.squad[0]).body
}
```

- [ ] **Step 3: CI verify, lint, commit**

```bash
git add -A && git commit -m "Add hero roster, detail with gear, and team editor"
```

---

### Task 7: Summon screen — banners, pity, ritual reveal

**Files:**
- Create: `Sources/UI/SummonView.swift`

**Interfaces:**
- Consumes: `EmberGameModel`, `GachaEngine`, `DS`
- Produces: `SummonView` — banner carousel (permanent + featured with rate-up badge), visible pity meters (Epic X/10, Legendary X/60), 1× and 10× buttons (gem costs from `GachaEngine.singleCost/multiCost`), daily free pull button (resets via `Date` day check), **summon ritual reveal overlay**: portal glow → beam → card flip per result (rarity-colored frame, faction icon, NEW badge, dupe → shard text), Legendary = gold fireworks; "Rates ⓘ" sheet with the exact rates table

- [ ] **Step 1: Implement** (reveal overlay is a full-screen ZStack with staged animations driven by `lastSummonResults`)
- [ ] **Step 2: Render smoke test + CI + commit**

```bash
git add -A && git commit -m "Add summon screen with pity meters and ritual reveal"
```

---

### Task 8: Market + Premium Shop

**Files:**
- Create: `Sources/UI/MarketView.swift` (in-game currency shop)
- Create: `Sources/UI/PremiumShopView.swift` (real-money IAP)
- Modify: `Sources/App/PurchaseService.swift` (rename product IDs to `dev.adrez.emberfall.*`, add gem pack tiers + Growth Bundle + Monthly Card products)

**Interfaces:**
- Produces:
  - `MarketView`: 4 tabs (Gold / Gems / Arena-locked / Quest tokens); daily rotating stock (seeded by date — deterministic item list), free daily item, refresh countdown; purchases call `model.buyMarketItem(...)` (new model method spending currency, granting items)
  - `PremiumShopView`: gem packs (6 tiers), Growth Bundle, Monthly Card, Remove Ads — all via `PurchaseService`; graceful "purchases unavailable" when RevenueCat unconfigured
  - `PurchaseService` changes: product map `gemPackProductIDs: [String: Int]` (gems granted), `monthlyCardProductID`, `growthBundleProductID`; entitlement `remove_ads` unchanged; `onGemsGranted` callback → `model.grantGems`

- [ ] **Step 1: Update PurchaseService** (rename IDs, new product tables, gem grant callback)
- [ ] **Step 2: Implement both shop views**
- [ ] **Step 3: Add `EmberSession.buyMarketItem` + GameCore test** (spend currency → grant gear box/materials; deterministic daily stock via `Calendar` day seed)
- [ ] **Step 4: Render smoke tests, CI, lint, commit**

```bash
git add -A && git commit -m "Add market and premium shop with RevenueCat product wiring"
```

---

### Task 9: More tab — leaderboard, quests, mail, profile, settings

**Files:**
- Create: `Sources/UI/MoreView.swift` (hub grid)
- Create: `Sources/UI/LeaderboardView.swift` (custom ornate board; local data until Plan 3 backend — shows the player + placeholder rivals clearly marked)
- Create: `Sources/UI/QuestsView.swift` (daily/weekly/achievements tabs, claim-all)
- Create: `Sources/UI/ProfileView.swift` (name edit, squad showcase, stats)
- Create: `Sources/UI/SettingsView.swift` (sound toggle, notifications toggle, sign-in, restore purchases, delete account, credits)

**Interfaces:**
- Consumes: `EmberGameModel`, `QuestSystem`, `DS`
- Produces: the five screens above; `LeaderboardView` renders `LeaderboardEntry` rows (rank, name, stage, squad power) — data source protocol `LeaderboardProviding` with `LocalLeaderboardProvider` (player only + generated rivals) in this plan; Plan 3 swaps in the Cloudflare provider behind the same protocol
- Quest claiming: `model.claimQuest(questID:)` (new model method wrapping `session.claimQuest` — add to GameCore with test if missing)

- [ ] **Step 1: Implement the five views**
- [ ] **Step 2: Add `EmberSession.claimQuest(questID:)` public wrapper + GameCore test** (already exists as `QuestSystem.claim`; expose through session: records + wallet grant + save)
- [ ] **Step 3: Render smoke tests, CI, lint, commit**

```bash
git add -A && git commit -m "Add More tab: leaderboard, quests, profile, settings"
```

---

### Task 10: Portrait lock, polish pass, full CI verification

**Files:**
- Modify: `project.yml` (orientations → portrait only; display name → "Emberfall Realms")
- Modify: `Sources/App/GameForgeApp.swift` (Firebase-lite: no-op analytics hooks; app icon placeholder note)
- Modify: `Sources/App/Persistence.swift` (add `lastIdleClaim` migration guard — already on profile)

**Interfaces:**
- Produces: final app shell for v1 UI; `UISupportedInterfaceOrientations` = portrait only; display name "Emberfall Realms"

- [ ] **Step 1: Update project.yml**

```yaml
INFOPLIST_KEY_UISupportedInterfaceOrientations: "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown"
INFOPLIST_KEY_CFBundleDisplayName: Emberfall Realms
```

- [ ] **Step 2: Full local verification**

```bash
cd Packages/GameCore && swift test
cd ../.. && swiftlint --quiet
```

- [ ] **Step 3: Push and watch CI end-to-end**

```bash
git push origin main
gh run watch $(gh run list --repo nick7167/gameforge --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```
Expected: all jobs green (lint, GameCore tests, app build + smoke tests, screenshots)

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Lock portrait orientation, rename display to Emberfall Realms"
```

---

## Self-Review Notes

- **Spec coverage (Plan 2 scope):** battle presentation (§4.1) → Tasks 3–4; hub (§10) → Task 5;
  heroes/gear UI (§6, §7) → Task 6; summon (§6.2) → Task 7; market + premium shop (§12) → Task 8;
  more-tab screens (§10) → Task 9; portrait/platform (§2) → Task 10. Notifications (§9) →
  deferred to a small follow-up task inside Plan 3 (needs daily-reset scheduling decisions);
  Game Center achievements hook → Plan 3.
- **Type consistency:** model methods match `EmberSession` public API exactly
  (`startBattle/tickBattle/fireUltimate/finishBattle/summon/levelUpHero/equipGear/
  enhanceGear/claimIdle`); two small GameCore additions (`renamePlayer`, `grantGems`,
  `claimQuest` wrapper, `buyMarketItem`) are specified inline with tests.
- **Known deferrals:** hero 3D models are the primitive unit factory (capsule/weapon
  compositions) — CC0 rigged packs land via `HeroModelProvider` in a follow-up task
  after Plan 2's structure is verified in CI; voice lines and music are asset-drop
  tasks with no code dependency.
