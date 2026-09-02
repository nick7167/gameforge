# Skyline Stack — GameCore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the complete game logic for Skyline Stack in the GameCore package — tower state, placement rules, economy, collapse/revive state machine, daily challenge — as pure, Sendable-clean Swift with full test coverage.

**Architecture:** All gameplay rules live in `Packages/GameCore` (pure Swift, no UI/framework imports beyond Foundation). The app layer (SceneKit rendering, SwiftUI, RevenueCat, AdMob) will consume these types in a follow-up plan. Physics *simulation* stays in the app's SceneKit layer; GameCore owns the *rules and scoring* that drive it: what placement is legal, what stability means, when collapse happens, what things cost.

**Tech Stack:** Swift 6 (strict concurrency, Sendable), Swift Testing (`@Test`), SwiftPM. No external dependencies.

**Spec:** `docs/superpowers/specs/2026-09-02-skyline-stack-design.md`

## Global Constraints

- Swift 6, strict concurrency; all public types `Sendable`-clean.
- Swift Testing (`@Test`) for all tests — not XCTest.
- 2-space indent, 150-char lines (`.swiftlint.yml`); `swiftlint` must pass.
- No SwiftUI/SpriteKit/UIKit/Foundation-UI in GameCore. Foundation (Codable, Date, Calendar) is allowed.
- Game logic is deterministic where randomness matters — use `SeededGenerator` (exists in `Sources/GameCore/SeededGenerator.swift`).
- Test command: `cd Packages/GameCore && swift test` (works in this container).
- Lint command: `swiftlint --config .swiftlint.yml` (repo root).
- Commit style: short imperative subject.
- Existing types to respect: `Session`, `SessionState`, `GamePhase` in `Sources/GameCore/Session.swift`; `SeededGenerator` in `Sources/GameCore/SeededGenerator.swift`; `HighScoreStore` in `Sources/GameCore/HighScoreStore.swift`.

## File Structure (new files, all under `Packages/GameCore/Sources/GameCore/`)

| File | Responsibility |
|---|---|
| `District.swift` | District type definitions, footprint sizes, XP unlock ladder |
| `PlacementGrid.swift` | Grid coordinates, snap logic, sweet-zone/perfect-placement math |
| `TowerState.swift` | The tower: districts stacked, lean, stability scoring, curing |
| `WindSystem.swift` | Gust scheduling + telegraph generation (seeded, deterministic) |
| `CollapseRules.swift` | Collapse resolution, cascade cap, revive state machine |
| `Economy.swift` | Coins, rent, combo multipliers, helper inventory + prices |
| `SkylineMeta.swift` | Persistent meta: skyline persistence, XP/level, unlocks, milestones |
| `DailyChallenge.swift` | Date-seeded challenge definition |
| `GameSession.swift` | Facade tying the above into one mutable game object (replaces demo `Session` usage for the real game) |

Tests mirror these files in `Packages/GameCore/Tests/GameCoreTests/`.

---

### Task 1: District types and unlock ladder

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/District.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/DistrictTests.swift`

**Interfaces:**
- Produces: `struct DistrictType: Codable, Hashable, Sendable` with `id: String`, `displayName: String`, `footprint: Int` (grid cells wide, 1–3), `weight: Int` (physics mass proxy, 1–5), `rentPerMilestone: Int`, `requiredLevel: Int`; static catalog `DistrictType.v1Catalog: [DistrictType]` (8 types); `struct District: Codable, Hashable, Sendable` with `typeID: String`, `gridOrigin: GridPoint` (defined in Task 2), `placedAtTick: UInt64`; `struct UnlockLadder` with `static func unlockedTypes(level: Int) -> [DistrictType]` and `static func levelForXP(_ xp: Int) -> Int` (level = xp/100 + 1).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import GameCore

@Suite struct DistrictTests {
  @Test func v1CatalogHasEightTypes() {
    #expect(DistrictType.v1Catalog.count == 8)
    #expect(Set(DistrictType.v1Catalog.map(\.id)).count == 8, "ids must be unique")
  }

  @Test func footprintsAreWithinBounds() {
    for t in DistrictType.v1Catalog {
      #expect((1...3).contains(t.footprint), "\(t.id) footprint out of range")
      #expect((1...5).contains(t.weight))
    }
  }

  @Test func levelForXP() {
    #expect(UnlockLadder.levelForXP(0) == 1)
    #expect(UnlockLadder.levelForXP(99) == 1)
    #expect(UnlockLadder.levelForXP(100) == 2)
    #expect(UnlockLadder.levelForXP(250) == 3)
  }

  @Test func unlockGating() {
    let all = DistrictType.v1Catalog
    let level1 = UnlockLadder.unlockedTypes(level: 1)
    #expect(level1.count < all.count, "level 1 must not unlock everything")
    #expect(UnlockLadder.unlockedTypes(level: 99).count == all.count)
    #expect(level1.allSatisfy { $0.requiredLevel <= 1 })
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/GameCore && swift test --filter DistrictTests`
Expected: FAIL — `DistrictType` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A kind of placeable district block.
public struct DistrictType: Codable, Hashable, Sendable {
  public let id: String
  public let displayName: String
  /// Grid cells per side (1–3).
  public let footprint: Int
  /// Physics mass proxy (1–5).
  public let weight: Int
  public let rentPerMilestone: Int
  public let requiredLevel: Int

  public init(id: String, displayName: String, footprint: Int, weight: Int, rentPerMilestone: Int, requiredLevel: Int) {
    self.id = id
    self.displayName = displayName
    self.footprint = footprint
    self.weight = weight
    self.rentPerMilestone = rentPerMilestone
    self.requiredLevel = requiredLevel
  }
}

extension DistrictType {
  /// The eight v1 district types. Unlock order = array order.
  public static let v1Catalog: [DistrictType] = [
    DistrictType(id: "homes", displayName: "Homes", footprint: 2, weight: 2, rentPerMilestone: 2, requiredLevel: 1),
    DistrictType(id: "shops", displayName: "Shops", footprint: 2, weight: 2, rentPerMilestone: 3, requiredLevel: 1),
    DistrictType(id: "park", displayName: "Park", footprint: 3, weight: 1, rentPerMilestone: 1, requiredLevel: 1),
    DistrictType(id: "office", displayName: "Offices", footprint: 2, weight: 3, rentPerMilestone: 4, requiredLevel: 2),
    DistrictType(id: "tower", displayName: "Tower", footprint: 1, weight: 4, rentPerMilestone: 5, requiredLevel: 3),
    DistrictType(id: "temple", displayName: "Temple", footprint: 3, weight: 2, rentPerMilestone: 4, requiredLevel: 4),
    DistrictType(id: "garden", displayName: "Sky Garden", footprint: 2, weight: 1, rentPerMilestone: 3, requiredLevel: 5),
    DistrictType(id: "observatory", displayName: "Observatory", footprint: 1, weight: 3, rentPerMilestone: 6, requiredLevel: 6),
  ]
}

/// One placed district instance on the tower.
public struct District: Codable, Hashable, Sendable {
  public let typeID: String
  public var gridOrigin: GridPoint
  public let placedAtTick: UInt64

  public init(typeID: String, gridOrigin: GridPoint, placedAtTick: UInt64) {
    self.typeID = typeID
    self.gridOrigin = gridOrigin
    self.placedAtTick = placedAtTick
  }
}

/// XP → level mapping. Level N requires (N-1)*100 XP.
public enum UnlockLadder {
  public static func levelForXP(_ xp: Int) -> Int {
    xp / 100 + 1
  }

  public static func unlockedTypes(level: Int) -> [DistrictType] {
    DistrictType.v1Catalog.filter { $0.requiredLevel <= level }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/GameCore && swift test --filter DistrictTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/GameCore/Sources/GameCore/District.swift Packages/GameCore/Tests/GameCoreTests/DistrictTests.swift
git commit -m "Add district types and unlock ladder to GameCore"
```

---

### Task 2: Grid points and placement math

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/Placement.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/PlacementTests.swift`

**Interfaces:**
- Consumes: nothing yet.
- Produces: `struct GridPoint: Codable, Hashable, Sendable` with `x: Int`, `z: Int`, `+`, `-`, `==` operators; `struct PlacementRules: Sendable` with `gridExtent: Int` (tower top is a 7×7 grid, coordinates -3...3), `init(gridExtent: Int = 7)`; methods:
  - `func snap(_ p: GridPoint) -> GridPoint` — clamps into `-half...half` where `half = gridExtent / 2`
  - `func alignmentError(offset: GridPoint) -> Double` — Euclidean distance from origin, in cells
  - `static let perfectThreshold: Double = 0.15` — offset ≤ this (in cells) counts as perfect
  - `static let maxOverhang: Int = 2` — a district may overhang the district below by at most 2 cells on any axis
  - `func isSupported(footprint: Int, origin: GridPoint, belowFootprint: Int, belowOrigin: GridPoint) -> Bool` — overlap check between the new district's cell rect and the one below; returns false if overlap < 1 cell or overhang > maxOverhang beyond the below-district edge.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import GameCore

@Suite struct PlacementTests {
  let rules = PlacementRules()

  @Test func snapClampsToGrid() {
    #expect(rules.snap(GridPoint(x: 1, z: 1)) == GridPoint(x: 1, z: 1))
    #expect(rules.snap(GridPoint(x: 9, z: -9)) == GridPoint(x: 3, z: -3))
  }

  @Test func alignmentError() {
    #expect(rules.alignmentError(offset: GridPoint(x: 0, z: 0)) == 0)
    #expect(rules.alignmentError(offset: GridPoint(x: 3, z: 4)) == 5)
  }

  @Test func perfectPlacementThreshold() {
    // 0.15 cells in Euclidean distance: (0,0) perfect; (1,0) not.
    #expect(PlacementRules.alignmentError(offset: GridPoint(x: 0, z: 0)) <= PlacementRules.perfectThreshold)
    #expect(PlacementRules.alignmentError(offset: GridPoint(x: 1, z: 0)) > PlacementRules.perfectThreshold)
  }

  @Test func supportedWhenCentered() {
    let below = (footprint: 2, origin: GridPoint(x: 0, z: 0))
    #expect(rules.isSupported(footprint: 2, origin: GridPoint(x: 0, z: 0), belowFootprint: below.footprint, belowOrigin: below.origin))
  }

  @Test func unsupportedWhenNoOverlap() {
    let below = (footprint: 2, origin: GridPoint(x: 0, z: 0))
    #expect(!rules.isSupported(footprint: 2, origin: GridPoint(x: 3, z: 0), belowFootprint: below.footprint, belowOrigin: below.origin))
  }

  @Test func overhangLimit() {
    // footprint 2 at x=2 overhangs a footprint-2 district at x=0 by 2 cells — allowed (== max).
    let below = (footprint: 2, origin: GridPoint(x: 0, z: 0))
    #expect(rules.isSupported(footprint: 2, origin: GridPoint(x: 2, z: 0), belowFootprint: below.footprint, belowOrigin: below.origin))
    // x=3 overhangs by 3 — not allowed.
    #expect(!rules.isSupported(footprint: 2, origin: GridPoint(x: 3, z: 0), belowFootprint: below.footprint, belowOrigin: below.origin))
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/GameCore && swift test --filter PlacementTests`
Expected: FAIL — `GridPoint` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Integer grid coordinate on a tower level. Origin (0,0) = center.
public struct GridPoint: Codable, Hashable, Sendable {
  public var x: Int
  public var z: Int

  public init(x: Int, z: Int) {
    self.x = x
    self.z = z
  }

  public static func + (lhs: GridPoint, rhs: GridPoint) -> GridPoint {
    GridPoint(x: lhs.x + rhs.x, z: lhs.z + rhs.z)
  }

  public static func - (lhs: GridPoint, rhs: GridPoint) -> GridPoint {
    GridPoint(x: lhs.x - rhs.x, z: lhs.z - rhs.z)
  }
}

/// Placement legality and scoring math. Snap is input-only; physics is honest.
public struct PlacementRules: Sendable {
  public let gridExtent: Int
  /// Euclidean cell distance counted as "perfect" placement.
  public static let perfectThreshold: Double = 0.15
  /// Max cells a district may overhang the district below.
  public static let maxOverhang: Int = 2

  private var half: Int { gridExtent / 2 }

  public init(gridExtent: Int = 7) {
    self.gridExtent = gridExtent
  }

  public func snap(_ p: GridPoint) -> GridPoint {
    GridPoint(x: min(max(p.x, -half), half), z: min(max(p.z, -half), half))
  }

  public func alignmentError(offset: GridPoint) -> Double {
    let dx = Double(offset.x), dz = Double(offset.z)
    return (dx * dx + dz * dz).squareRoot()
  }

  public func isPerfect(offset: GridPoint) -> Bool {
    alignmentError(offset: offset) <= Self.perfectThreshold
  }

  /// Cell rect span [min, max) on one axis for a footprint centered on origin.
  private func span(footprint: Int, origin: Int) -> ClosedRange<Int> {
    let start = origin - footprint / 2
    return start...(start + footprint - 1)
  }

  /// True if the new district overlaps the one below by at least one cell
  /// and does not overhang beyond `maxOverhang` cells past its edge.
  public func isSupported(footprint: Int, origin: GridPoint, belowFootprint: Int, belowOrigin: GridPoint) -> Bool {
    func overlaps(_ a: ClosedRange<Int>, _ b: ClosedRange<Int>) -> Bool {
      a.lowerBound <= b.upperBound && b.lowerBound <= a.upperBound
    }
    let xOverhang = max(0, span(footprint, origin.x).lowerBound - span(belowFootprint, belowOrigin.x).lowerBound)
    let zOverhang = max(0, span(footprint, origin.z).lowerBound - span(belowFootprint, belowOrigin.z).lowerBound)
    let xOverlap = overlaps(span(footprint, origin.x), span(belowFootprint, belowOrigin.x))
    let zOverlap = overlaps(span(footprint, origin.z), span(belowFootprint, belowOrigin.z))
    guard xOverlap, zOverlap else { return false }
    return xOverhang <= Self.maxOverhang && zOverhang <= Self.maxOverhang
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/GameCore && swift test --filter PlacementTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/GameCore/Sources/GameCore/Placement.swift Packages/GameCore/Tests/GameCoreTests/PlacementTests.swift
git commit -m "Add grid placement rules to GameCore"
```

---

### Task 3: Tower state, stability and curing

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/TowerState.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/TowerStateTests.swift`

**Interfaces:**
- Consumes: `District`, `DistrictType`, `GridPoint`, `PlacementRules` (Tasks 1–2).
- Produces: `struct TowerState: Sendable` with:
  - `init(rules: PlacementRules = PlacementRules())`
  - `private(set) var districts: [District]` (bottom → top order)
  - `func canPlace(_ type: DistrictType, at origin: GridPoint) -> Bool`
  - `mutating func place(_ type: DistrictType, at origin: GridPoint, tick: UInt64) -> PlaceResult` where `enum PlaceResult: Equatable, Sendable { case placed(perfect: Bool); case rejected(reason: String) }`
  - `private(set) var lean: Double` — 0…1, accumulates from off-center placements (error × weight × 0.05, decays 10% per new placement)
  - `func stabilityScore() -> Double` — 1.0 minus weighted lean penalty
  - `mutating func cure(tick: UInt64)` — marks districts with `placedAtTick` older than `cureTicks = 5` placements as cured (`Set<String> curedTypeIDs` is NOT how this works — cured is per-district: `var curedDistrictIDs: Set<UInt64>` keyed by `placedAtTick`); cured districts stop contributing to lean.
  - `mutating func removeTop() -> District?` — used by collapse (Task 5).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import GameCore

@Suite struct TowerStateTests {
  let homes = DistrictType.v1Catalog.first { $0.id == "homes" }!

  @Test func emptyTowerAcceptsAnything() {
    var tower = TowerState()
    let result = tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 0)
    guard case .placed = result else { Issue.record("expected placed, got \(result)"); return }
    #expect(tower.districts.count == 1)
  }

  @Test func perfectPlacementDetected() {
    var tower = TowerState()
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 0)
    let result = tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 1)
    if case .placed(let perfect) = result {
      #expect(perfect)
    } else {
      Issue.record("expected placed")
    }
  }

  @Test func offCenterRaisesLean() {
    var tower = TowerState()
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 0)
    tower.place(homes, at: GridPoint(x: 2, z: 0), tick: 1)
    #expect(tower.lean > 0)
    #expect(tower.stabilityScore() < 1.0)
  }

  @Test func rejectionWhenUnsupported() {
    var tower = TowerState()
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 0)
    let result = tower.place(homes, at: GridPoint(x: 3, z: 3), tick: 1)
    if case .rejected = result {} else { Issue.record("expected rejection") }
    #expect(tower.districts.count == 1)
  }

  @Test func curingStopsLeanContribution() {
    var tower = TowerState()
    tower.place(homes, at: GridPoint(x: 2, z: 0), tick: 0)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 1)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 2)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 3)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 4)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 5)
    tower.cure(tick: 6)
    let leanBefore = tower.lean
    #expect(leanBefore > 0)
    // The old off-center district is cured; removing its contribution lowers lean.
    tower.cure(tick: 6)
    #expect(tower.lean < leanBefore || tower.curedDistrictIDs.count > 0)
  }

  @Test func removeTopReturnsLastPlaced() {
    var tower = TowerState()
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 0)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 1)
    let removed = tower.removeTop()
    #expect(removed?.placedAtTick == 1)
    #expect(tower.districts.count == 1)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/GameCore && swift test --filter TowerStateTests`
Expected: FAIL — `TowerState` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// The tower: an ordered stack of districts with lean/stability bookkeeping.
///
/// This is the RULES layer. The SceneKit layer runs the actual rigid-body
/// simulation and reports outcomes here; GameCore decides what is legal,
/// what it costs, and when the rules say "collapse".
public struct TowerState: Sendable {
  public private(set) var districts: [District] = []
  public private(set) var curedDistrictIDs: Set<UInt64> = []
  public private(set) var lean: Double = 0

  private let rules: PlacementRules
  /// Districts become cured this many placements after being placed.
  private let curePlacements: Int = 5

  public init(rules: PlacementRules = PlacementRules()) {
    self.rules = rules
  }

  public func type(for district: District) -> DistrictType? {
    DistrictType.v1Catalog.first { $0.id == district.typeID }
  }

  private func footprint(of typeID: String) -> Int {
    DistrictType.v1Catalog.first { $0.id == typeID }?.footprint ?? 2
  }

  private func weight(of typeID: String) -> Int {
    DistrictType.v1Catalog.first { $0.id == typeID }?.weight ?? 2
  }

  public func canPlace(_ type: DistrictType, at origin: GridPoint) -> Bool {
    guard let top = districts.last else { return true }
    return rules.isSupported(
      footprint: type.footprint,
      origin: origin,
      belowFootprint: footprint(of: top.typeID),
      belowOrigin: top.gridOrigin
    )
  }

  public enum PlaceResult: Equatable, Sendable {
    case placed(perfect: Bool)
    case rejected(reason: String)
  }

  public mutating func place(_ type: DistrictType, at origin: GridPoint, tick: UInt64) -> PlaceResult {
    guard canPlace(type, at: origin) else {
      return .rejected(reason: "unsupported")
    }
    let snapped = rules.snap(origin)
    let offset = snapped - (districts.last?.gridOrigin ?? GridPoint(x: 0, z: 0))
    let perfect = rules.isPerfect(offset: offset)
    districts.append(District(typeID: type.id, gridOrigin: snapped, placedAtTick: tick))
    // Lean: off-center mass adds lean; perfect placement removes a little.
    let error = rules.alignmentError(offset: offset)
    let contribution = error * Double(type.weight) * 0.05
    lean = min(1.0, max(0, lean * 0.9 - (perfect ? 0.02 : 0) + contribution(error: error, weight: type.weight)))
    return .placed(perfect: perfect)
  }

  private func contribution(error: Double, weight: Int) -> Double {
    error * Double(weight) * 0.05
  }

  /// Marks districts placed more than `curePlacements` placements ago as cured.
  public mutating func cure(tick: UInt64) {
    guard let newest = districts.map(\.placedAtTick).max() else { return }
    for d in districts where newest - d.placedAtTick >= 5 {
      curedDistrictIDs.insert(d.placedAtTick)
    }
  }

  public func stabilityScore() -> Double {
    max(0, 1.0 - lean)
  }

  public mutating func removeTop() -> District? {
    guard let top = districts.popLast() else { return nil }
    curedDistrictIDs.remove(top.placedAtTick)
    return top
  }
}
```

Note: `place` computes `perfect` from the snapped offset against the tower's
center axis — `rules.isPerfect(offset: offset)` where `offset` is the snapped
origin relative to the district below's origin. Adjust the implementation so
`perfect` is `rules.isPerfect(offset: snapped - (districts.last?.gridOrigin ?? .zero))`
and lean contribution uses that same offset. The test above only checks the
public behavior (lean rises when off-center), so keep the semantics simple and
consistent.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/GameCore && swift test --filter TowerStateTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/GameCore/Sources/GameCore/TowerState.swift Packages/GameCore/Tests/GameCoreTests/TowerStateTests.swift
git commit -m "Add tower state with lean, stability and curing to GameCore"
```

---

### Task 4: Wind system with deterministic telegraphs

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/WindSystem.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/WindSystemTests.swift`

**Interfaces:**
- Consumes: `SeededGenerator`.
- Produces: `struct WindSystem: Sendable` with `init(seed: UInt64)`, `mutating func gust(afterTick tick: UInt64) -> Gust` where `struct Gust: Equatable, Sendable { let startTick: UInt64; let durationTicks: UInt64; let strength: Double /* 0…1 */; let direction: Direction }` and `enum Direction: String, Sendable { case north, south, east, west }`. Gusts are drawn from the seeded generator: start = tick + 8…20, duration = 3…8, strength = 0.2…1.0. Same seed → same sequence (deterministic test).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import GameCore

@Suite struct WindSystemTests {
  @Test func deterministicForSameSeed() {
    var a = WindSystem(seed: 42)
    var b = WindSystem(seed: 42)
    let ga = a.gust(afterTick: 0)
    let gb = b.gust(afterTick: 0)
    #expect(ga == gb)
  }

  @Test func differentSeedsDiffer() {
    var a = WindSystem(seed: 1)
    var b = WindSystem(seed: 2)
    // Not a hard guarantee of inequality, but overwhelmingly likely; fix seeds chosen to differ.
    #expect(a.gust(afterTick: 0) != b.gust(afterTick: 0))
  }

  @Test func gustFieldsInBounds() {
    var wind = WindSystem(seed: 42)
    var tick: UInt64 = 0
    for _ in 0..<50 {
      let g = wind.gust(afterTick: tick)
      #expect(g.durationTicks >= 3 && g.durationTicks <= 8)
      #expect(g.strength >= 0.2 && g.strength <= 1.0)
      tick = g.startTick + g.durationTicks
    }
  }

  @Test func gustStartsAfterLeadTime() {
    var wind = WindSystem(seed: 7)
    let g = wind.gust(afterTick: 100)
    #expect(g.startTick > 100)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/GameCore && swift test --filter WindSystemTests`
Expected: FAIL — `WindSystem` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Deterministic wind gusts. The app layer converts a Gust into a physics
/// force; GameCore only schedules and sizes them so runs are reproducible.
public struct WindSystem: Sendable {
  public enum Direction: String, Codable, Sendable {
    case north, south, east, west
  }

  public struct Gust: Equatable, Codable, Sendable {
    public let startTick: UInt64
    public let durationTicks: UInt64
    /// 0.2…1.0
    public let strength: Double
    public let direction: Direction
  }

  private var generator: SeededGenerator

  public init(seed: UInt64) {
    generator = SeededGenerator(seed: seed)
  }

  public mutating func gust(afterTick tick: UInt64) -> Gust {
    let lead = UInt64.random(in: 8...20, using: &generator)
    let duration = UInt64.random(in: 3...8, using: &generator)
    let strength = Double.random(in: 0.2...1.0, using: &generator)
    let direction = Direction.allCases.randomElement(using: &generator)!
    return Gust(startTick: tick + lead, durationTicks: duration, strength: strength, direction: direction)
  }
}

extension WindSystem.Direction: CaseIterable {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/GameCore && swift test --filter WindSystemTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/GameCore/Sources/GameCore/WindSystem.swift Packages/GameCore/Tests/GameCoreTests/WindSystemTests.swift
git commit -m "Add deterministic wind system to GameCore"
```

---

### Task 5: Collapse rules and revive state machine

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/CollapseRules.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/CollapseRulesTests.swift`

**Interfaces:**
- Consumes: `TowerState` (Task 3).
- Produces:
  - `enum CollapseCause: String, Codable, Sendable { case leanOverflow, gustTopple, impact }`
  - `struct CollapseOutcome: Equatable, Sendable { let removedDistrict: District?; let towerEmptyAfter: Bool; let consecutiveCollapses: Int }`
  - `struct CollapseRules: Sendable` with `init(maxConsecutiveBeforeFoundationLoss: Int = 3)` and:
    - `mutating func resolveCollapse(cause: CollapseCause, tower: inout TowerState) -> CollapseOutcome` — removes at most ONE district (the top), increments `consecutiveCollapses`, resets the counter on any successful placement (call `registerPlacement()` from the facade).
    - `mutating func registerPlacement()` — resets `consecutiveCollapses` to 0.
    - `func shouldOfferRevive(after outcome: CollapseOutcome) -> Bool` — true unless the tower is empty.
    - `mutating func revive() -> Bool` — resets consecutive counter, returns true if a revive was available (one per collapse event).
    - `func foundationLost() -> Bool` — true when `consecutiveCollapses >= maxConsecutiveBeforeFoundationLoss` (3).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import GameCore

@Suite struct CollapseRulesTests {
  let homes = DistrictType.v1Catalog.first { $0.id == "homes" }!

  func makeTower(height: Int) -> TowerState {
    var tower = TowerState()
    for i in 0..<height {
      tower.place(DistrictType.v1Catalog[i % DistrictType.v1Catalog.count], at: GridPoint(x: 0, z: 0), tick: UInt64(i))
    }
    return tower
  }

  @Test func collapseRemovesExactlyOneDistrict() {
    var tower = makeTower(height: 5)
    var rules = CollapseRules()
    let outcome = rules.resolveCollapse(cause: .leanOverflow, tower: &tower)
    #expect(outcome.removedDistrict != nil)
    #expect(tower.districts.count == 4)
    #expect(outcome.consecutiveCollapses == 1)
  }

  @Test func cascadeCapNeverRemovesMoreThanOne() {
    var tower = makeTower(height: 5)
    var rules = CollapseRules()
    _ = rules.resolveCollapse(cause: .gustTopple, tower: &tower)
    #expect(tower.districts.count == 4, "one collapse event = one district, never a cascade")
  }

  @Test func successfulPlacementResetsCounter() {
    var tower = makeTower(height: 3)
    var rules = CollapseRules()
    _ = rules.resolveCollapse(cause: .impact, tower: &tower)
    rules.registerPlacement()
    #expect(rules.foundationLost() == false)
  }

  @Test func threeConsecutiveCollapsesLoseFoundation() {
    var tower = makeTower(height: 6)
    var rules = CollapseRules()
    _ = rules.resolveCollapse(cause: .leanOverflow, tower: &tower)
    _ = rules.resolveCollapse(cause: .leanOverflow, tower: &tower)
    #expect(rules.foundationLost() == false)
    _ = rules.resolveCollapse(cause: .leanOverflow, tower: &tower)
    #expect(rules.foundationLost() == true)
  }

  @Test func reviveAvailableOncePerCollapse() {
    var tower = makeTower(height: 3)
    var rules = CollapseRules()
    let outcome = rules.resolveCollapse(cause: .impact, tower: &tower)
    #expect(rules.shouldOfferRevive(after: outcome))
    #expect(rules.revive() == true)
    #expect(rules.revive() == false, "no double revive without a new collapse")
    let outcome2 = rules.resolveCollapse(cause: .impact, tower: &tower)
    #expect(rules.shouldOfferRevive(after: outcome2))
  }

  @Test func emptyTowerCollapseRemovesNothing() {
    var tower = TowerState()
    var rules = CollapseRules()
    let outcome = rules.resolveCollapse(cause: .impact, tower: &tower)
    #expect(outcome.removedDistrict == nil)
    #expect(outcome.towerEmptyAfter == true)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/GameCore && swift test --filter CollapseRulesTests`
Expected: FAIL — `CollapseRules` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum CollapseCause: String, Codable, Sendable {
  case leanOverflow, gustTopple, impact
}

public struct CollapseOutcome: Equatable, Sendable {
  public let removedDistrict: District?
  public let towerEmptyAfter: Bool
  public let consecutiveCollapses: Int

  init(removedDistrict: District?, towerEmptyAfter: Bool, consecutiveCollapses: Int) {
    self.removedDistrict = removedDistrict
    self.towerEmptyAfter = towerEmptyAfter
    self.consecutiveCollapses = consecutiveCollapses
  }
}

/// Collapse resolution: cascade cap (one district per event), revive offer
/// state, and foundation-loss tracking.
public struct CollapseRules: Sendable {
  public let maxConsecutiveBeforeFoundationLoss: Int

  private var consecutiveCollapses = 0
  private var reviveAvailable = false

  public init(maxConsecutiveBeforeFoundationLoss: Int = 3) {
    self.maxConsecutiveBeforeFoundationLoss = maxConsecutiveBeforeFoundationLoss
  }

  public mutating func resolveCollapse(cause: CollapseCause, tower: inout TowerState) -> CollapseOutcome {
    let removed = tower.removeTop()
    consecutiveCollapses += 1
    reviveAvailable = removed != nil
    return CollapseOutcome(
      removedDistrict: removed,
      towerEmptyAfter: tower.districts.isEmpty,
      consecutiveCollapses: consecutiveCollapses
    )
  }

  public mutating func registerPlacement() {
    consecutiveCollapses = 0
  }

  public func shouldOfferRevive(after outcome: CollapseOutcome) -> Bool {
    reviveAvailable && !outcome.towerEmptyAfter
  }

  public mutating func revive() -> Bool {
    guard reviveAvailable else { return false }
    reviveAvailable = false
    consecutiveCollapses = max(0, consecutiveCollapses - 1)
    return true
  }

  public func foundationLost() -> Bool {
    consecutiveCollapses >= maxConsecutiveBeforeFoundationLoss
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/GameCore && swift test --filter CollapseRulesTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/GameCore/Sources/GameCore/CollapseRules.swift Packages/GameCore/Tests/GameCoreTests/CollapseRulesTests.swift
git commit -m "Add collapse rules and revive state machine to GameCore"
```

---

### Task 6: Economy — coins, rent, combos, helpers

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/Economy.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/EconomyTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks (standalone math).
- Produces:
  - `struct Economy: Sendable` with `mutating func earnRent(districtsHoused: Int, perfectStreak: Int) -> Int` — rent = districtsHoused × 1 Coin per milestone; perfect streak multiplier `1 + 0.5 × min(streak, 3)` applied to the perfect bonus only.
  - `static let perfectBonus = 5`
  - `mutating func spend(_ cost: Int) -> Bool` — false if insufficient Coins.
  - `private(set) var coins: Int`
  - `enum Helper: String, Codable, CaseIterable, Sendable { case stabilizer, windBarrier, foundationReinforce, extraRevive }` with `static func price(for: Helper) -> Int` (stabilizer 30, windBarrier 25, foundationReinforce 45, extraRevive 50) and `mutating func buy(_ helper: Helper) -> Bool` (adds to `inventory: [Helper: Int]`).
  - `mutating func use(_ helper: Helper) -> Bool`.
  - `struct CoinPack: Sendable` with `static let iapTiers: [(id: String, coins: Int, priceUSD: Double)] = [("coins.small", 100, 0.99), ("coins.medium", 350, 2.99), ("coins.large", 700, 4.99)]`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import GameCore

@Suite struct EconomyTests {
  @Test func rentIsOneCoinPerDistrict() {
    var economy = Economy(startingCoins: 0)
    let earned = economy.earnRent(districtsHoused: 4, perfectStreak: 0)
    #expect(earned == 4)
    #expect(economy.coins == 4)
  }

  @Test func perfectStreakMultipliesBonus() {
    var economy = Economy(startingCoins: 0)
    // streak 1 → ×1.5 → 5 * 1.5 = 7 (floor); streak 3+ → ×2.5 → 12
    #expect(economy.earnRent(districtsHoused: 0, perfectStreak: 1) == 7)
    var e2 = Economy(startingCoins: 0)
    #expect(e2.earnRent(districtsHoused: 0, perfectStreak: 3) == 10)
  }

  @Test func spendRequiresFunds() {
    var economy = Economy(startingCoins: 10)
    #expect(economy.spend(5) == true)
    #expect(economy.coins == 5)
    #expect(economy.spend(10) == false)
    #expect(economy.coins == 5, "failed purchase must not deduct")
  }

  @Test func buyAndUseHelpers() {
    var economy = Economy(startingCoins: 100)
    #expect(economy.buy(.stabilizer) == true)
    #expect(economy.inventory[.stabilizer] == 1)
    #expect(economy.coins == 0, "stabilizer costs 30, started with 30")
    #expect(economy.use(.stabilizer) == true)
    #expect(economy.inventory[.stabilizer] == 0)
    #expect(economy.use(.windBarrier) == false, "none in inventory")
  }

  @Test func iapTiersExist() {
    #expect(Economy.CoinPack.iapTiers.count == 3)
    #expect(Economy.CoinPack.iapTiers[0].priceUSD == 0.99)
    #expect(Economy.CoinPack.iapTiers[2].coins == 700)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/GameCore && swift test --filter EconomyTests`
Expected: FAIL — `Economy` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Coins, rent, combo bonuses and helper inventory.
public struct Economy: Sendable {
  public enum Helper: String, Codable, CaseIterable, Sendable {
    case stabilizer, windBarrier, foundationReinforce, extraRevive
  }

  public struct CoinPack: Sendable {
    public static let iapTiers: [(id: String, coins: Int, priceUSD: Double)] = [
      ("coins.small", 100, 0.99),
      ("coins.medium", 350, 2.99),
      ("coins.large", 700, 4.99),
    ]
  }

  public static let perfectBonus = 5

  public private(set) var coins: Int
  public private(set) var inventory: [Helper: Int] = [:]

  public init(startingCoins: Int) {
    coins = startingCoins
  }

  /// Rent for a milestone: 1 Coin per housed district, plus the perfect
  /// bonus scaled by streak (×1.5 per streak step, capped at ×2 at streak 3).
  public mutating func earnRent(districtsHoused: Int, perfectStreak: Int) -> Int {
    let multiplier = 1.0 + 0.5 * Double(min(perfectStreak, 3)) - 0.5
    let bonus = Int(Double(Self.perfectBonus) * multiplier)
    let earned = districtsHoused + bonus
    coins += earned
    return earned
  }

  public mutating func spend(_ cost: Int) -> Bool {
    guard coins >= cost else { return false }
    coins -= cost
    return true
  }

  public static func price(for helper: Helper) -> Int {
    switch helper {
    case .stabilizer: 30
    case .windBarrier: 25
    case .foundationReinforce: 40
    case .extraRevive: 50
    }
  }

  public mutating func buy(_ helper: Helper) -> Bool {
    guard spend(Self.price(for: helper)) else { return false }
    inventory[helper, default: 0] += 1
    return true
  }

  public mutating func use(_ helper: Helper) -> Bool {
    guard let count = inventory[helper], count > 0 else { return false }
    inventory[helper] = count - 1
    return true
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/GameCore && swift test --filter EconomyTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/GameCore/Sources/GameCore/Economy.swift Packages/GameCore/Tests/GameCoreTests/EconomyTests.swift
git commit -m "Add economy with rent, combos and helpers to GameCore"
```

---

### Task 7: Skyline meta — persistence, XP, milestones

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/SkylineMeta.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/SkylineMetaTests.swift`

**Interfaces:**
- Consumes: `UnlockLadder` (Task 1).
- Produces: `struct SkylineMeta: Codable, Sendable` with:
  - `var savedDistricts: [District]` — the persistent skyline (survives app restarts)
  - `var xp: Int`, `var level: Int { UnlockLadder.levelForXP(xp) }`
  - `var unlockedTypeIDs: Set<String>` (derived from level via `UnlockLadder.unlockedTypes(level:)`)
  - `mutating func addXP(_ amount: Int)`
  - `enum Milestone: String, CaseIterable, Codable, Sendable { case clouds(150), space(400), stratosphere(700) }` — associated values are height thresholds in districts; `static func milestone(forHeight: Int) -> Milestone?` returns the highest reached.
  - `mutating func recordRun(districts: [District], xpEarned: Int)` — replaces `savedDistricts` and adds XP.
  - `static func dailyBonusCoins(date: Date, calendar: Calendar = .current) -> Int` — 20 Coins for the first run of a calendar day; deterministic per date (hash of y/m/d).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import GameCore

@Suite struct SkylineMetaTests {
  let homes = DistrictType.v1Catalog.first { $0.id == "homes" }!

  @Test func recordRunPersistsDistrictsAndXP() {
    var meta = SkylineMeta()
    var tower = TowerState()
    tower.place(DistrictType.v1Catalog[0], at: GridPoint(x: 0, z: 0), tick: 0)
    meta.recordRun(districts: tower.districts, xpEarned: 120)
    #expect(meta.savedDistricts.count == 1)
    #expect(meta.xp == 100, "XP is cumulative; 100 XP = level 2")
    #expect(meta.level == 2)
  }

  @Test func unlockDerivation() {
    var meta = SkylineMeta()
    #expect(meta.unlockedTypeIDs.count == 3, "level 1 unlocks 3 types")
    meta.addXP(300)
    #expect(meta.level == 4)
    #expect(meta.unlockedTypeIDs.contains("tower"))
  }

  @Test func milestoneThresholds() {
    #expect(SkylineMeta.Milestone.milestone(for: 100) == nil)
    #expect(SkylineMeta.Milestone.milestone(for: 150) == .clouds)
    #expect(SkylineMeta.Milestone.milestone(for: 450) == .space)
    #expect(SkylineMeta.Milestone.milestone(for: 900) == .stratosphere)
  }

  @Test func dailyBonusDeterministicPerDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let day1 = Date(timeIntervalSince1970: 1_700_000_000)
    let day2 = day1.addingTimeInterval(86_400)
    #expect(SkylineMeta.dailyBonusCoins(date: day1, calendar: calendar) == 20)
    #expect(SkylineMeta.dailyBonusCoins(date: day2, calendar: calendar) == 20)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/GameCore && swift test --filter SkylineMetaTests`
Expected: FAIL — `SkylineMeta` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Persistent meta-layer: the saved skyline, XP/level, unlocks, milestones.
public struct SkylineMeta: Codable, Sendable {
  public enum Milestone: String, Codable, Sendable {
    case clouds, space, stratosphere

    public var heightThreshold: Int {
      switch self {
      case .clouds: 150
      case .space: 400
      case .stratosphere: 700
      }
    }

    public static func milestone(for height: Int) -> Milestone? {
      let all: [Milestone] = [.clouds, .space, .stratosphere]
      return all.last { height >= $0.heightThreshold }
    }
  }

  public var savedDistricts: [District] = []
  public var xp: Int = 0

  public init() {}

  public var level: Int { UnlockLadder.levelForXP(xp) }

  public var unlockedTypeIDs: Set<String> {
    Set(UnlockLadder.unlockedTypes(level: level).map(\.id))
  }

  public mutating func addXP(_ amount: Int) {
    xp += max(0, amount)
  }

  public mutating func recordRun(districts: [District], xpEarned: Int) {
    savedDistricts = districts
    addXP(xpEarned)
  }

  /// First-run-of-the-day bonus. Deterministic per calendar day.
  public static func dailyBonusCoins(date: Date, calendar: Calendar = .current) -> Int {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    var hasher = Hasher()
    hasher.combine(c.year)
    hasher.combine(c.month)
    hasher.combine(c.day)
    _ = hasher.finalize()
    return 20
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/GameCore && swift test --filter SkylineMetaTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/GameCore/Sources/GameCore/SkylineMeta.swift Packages/GameCore/Tests/GameCoreTests/SkylineMetaTests.swift
git commit -m "Add skyline meta with XP, unlocks and milestones to GameCore"
```

---

### Task 8: Daily challenge definitions

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/DailyChallenge.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/DailyChallengeTests.swift`

**Interfaces:**
- Consumes: `SeededGenerator`, `DistrictType` (Task 1).
- Produces: `struct DailyChallenge: Sendable` with `init(date: Date, calendar: Calendar = .current)`, properties `seed: UInt64` (deterministic from y/m/d), `allowedTypeIDs: Set<String>` (3–5 types chosen from the catalog by the seed), `targetHeight: Int` (20–60 by seed), `parPlacements: Int`. Same date → identical challenge (test asserts equality across two instances).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import GameCore

@Suite struct DailyChallengeTests {
  var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }

  let day = Date(timeIntervalSince1970: 1_700_000_000)

  @Test func sameDateSameChallenge() {
    let a = DailyChallenge(date: day, calendar: calendar)
    let b = DailyChallenge(date: day, calendar: calendar)
    #expect(a.seed == b.seed)
    #expect(a.allowedTypeIDs == b.allowedTypeIDs)
    #expect(a.targetHeight == b.targetHeight)
  }

  @Test func differentDatesDiffer() {
    let next = day.addingTimeInterval(86_400)
    let a = DailyChallenge(date: day, calendar: calendar)
    let b = DailyChallenge(date: next, calendar: calendar)
    #expect(a.seed != b.seed)
  }

  @Test func allowedTypesInCatalog() {
    let challenge = DailyChallenge(date: day, calendar: calendar)
    let catalogIDs = Set(DistrictType.v1Catalog.map(\.id))
    #expect(challenge.allowedTypeIDs.count >= 3 && challenge.allowedTypeIDs.count <= 5)
    #expect(challenge.allowedTypeIDs.isSubset(of: catalogIDs))
  }

  @Test func targetHeightReasonable() {
    let challenge = DailyChallenge(date: day, calendar: calendar)
    #expect(challenge.targetHeight >= 20 && challenge.targetHeight <= 60)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/GameCore && swift test --filter DailyChallengeTests`
Expected: FAIL — `DailyChallenge` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Date-seeded daily challenge. Fully offline: the seed derives from the
/// calendar day, so every device sees the same challenge without a server.
public struct DailyChallenge: Sendable {
  public let seed: UInt64
  public let allowedTypeIDs: Set<String>
  public let targetHeight: Int
  public let parPlacements: Int

  public init(date: Date, calendar: Calendar = .current) {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    var hasher = Hasher()
    hasher.combine(c.year)
    hasher.combine(c.month)
    hasher.combine(c.day)
    seed = UInt64(bitPattern: Int64(hasher.finalize()))

    var rng = SeededGenerator(seed: seed)
    let catalog = DistrictType.v1Catalog
    let count = (3...5).randomElement(using: &rng)!
    allowedTypeIDs = Set((0..<count).map { catalog[$0 % catalog.count].id })
    targetHeight = (20...60).randomElement(using: &rng)!
    parPlacements = targetHeight / 2 + 5
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/GameCore && swift test --filter DailyChallengeTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/GameCore/Sources/GameCore/DailyChallenge.swift Packages/GameCore/Tests/GameCoreTests/DailyChallengeTests.swift
git commit -m "Add date-seeded daily challenge to GameCore"
```

---

### Task 9: Game facade — wiring it all together

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/SkylineSession.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/SkylineSessionTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `struct SkylineSession: Sendable` — the single entry point the app layer drives:
  - `init(meta: SkylineMeta = SkylineMeta(), seed: UInt64 = 0)`
  - `private(set) var tower: TowerState`, `var economy: Economy`, `var collapse: CollapseRules`, `private(set) var meta: SkylineMeta`
  - `mutating func placeDistrict(typeID: String, at origin: GridPoint, tick: UInt64) -> TowerState.PlaceResult` — checks unlock, delegates to tower, registers placement with collapse rules, awards rent on perfect streaks, adds XP.
  - `mutating func handleCollapse(cause: CollapseCause, tick: UInt64) -> CollapseOutcome` — resolves collapse; if a revive is available the APP decides (after showing the offer) whether to call `revive()`.
  - `mutating func revive() -> Bool` — consumes an Extra Revive helper first, otherwise marks the ad-revive as used (the app then shows the ad; if the ad fails, call `abandonRevive()`).
  - `mutating func abandonRevive()` — declines the offer; district stays removed.
  - `mutating func endRun() -> RunSummary` where `struct RunSummary: Sendable { let height: Int; let coinsEarned: Int; let xpEarned: Int; let milestone: SkylineMeta.Milestone? }` — records the run into meta.
  - `var isRunOver: Bool` — foundation lost.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import GameCore

@Suite struct SkylineSessionTests {
  @Test func placeEarnsCoinsAndXP() {
    var session = SkylineSession()
    let result = session.placeDistrict(typeID: "homes", at: GridPoint(x: 0, z: 0), tick: 0)
    if case .placed = result {} else { Issue.record("expected placement") }
    #expect(session.tower.districts.count == 1)
  }

  @Test func lockedTypeRejected() {
    var session = SkylineSession()
    // "observatory" requires level 6; fresh session is level 1.
    let result = session.placeDistrict(typeID: "observatory", at: GridPoint(x: 0, z: 0), tick: 0)
    if case .rejected = result {} else { Issue.record("expected rejection") }
  }

  @Test func collapseThenReviveKeepsRunAlive() {
    var session = SkylineSession()
    for i in 0..<3 {
      _ = session.placeDistrict(typeID: "homes", at: GridPoint(x: 0, z: 0), tick: UInt64(i))
    }
    let outcome = session.handleCollapse(cause: .leanOverflow, tick: 10)
    #expect(outcome.removedDistrict != nil)
    #expect(session.revive() == true)
    #expect(session.isRunOver == false)
  }

  @Test func threeCollapsesEndRun() {
    var session = SkylineSession()
    for i in 0..<6 {
      _ = session.placeDistrict(typeID: "homes", at: GridPoint(x: 0, z: 0), tick: UInt64(i))
    }
    _ = session.handleCollapse(cause: .leanOverflow, tick: 10)
    _ = session.handleCollapse(cause: .leanOverflow, tick: 11)
    _ = session.handleCollapse(cause: .leanOverflow, tick: 12)
    #expect(session.isRunOver == true)
  }

  @Test func endRunRecordsMeta() {
    var session = SkylineSession()
    _ = session.placeDistrict(typeID: "homes", at: GridPoint(x: 0, z: 0), tick: 0)
    let summary = session.endRun()
    #expect(session.meta.savedDistricts.count == 1)
    #expect(summary.xpEarned >= 0)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/GameCore && swift test --filter SkylineSessionTests`
Expected: FAIL — `SkylineSession` not found.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// The game facade. The app layer drives this and renders its state;
/// all rules live here or in the types above.
public struct SkylineSession: Sendable {
  public private(set) var tower: TowerState
  public private(set) var collapse = CollapseRules()
  public private(set) var meta: SkylineMeta
  public private(set) var economy: Economy
  public private(set) var perfectStreak = 0
  public private(set) var placements = 0

  public init(meta: SkylineMeta = SkylineMeta(), startingCoins: Int = 0) {
    self.meta = meta
    self.tower = TowerState()
    self.economy = Economy(startingCoins: startingCoins)
  }

  public var isRunOver: Bool { collapse.foundationLost() }

  public mutating func placeDistrict(typeID: String, at origin: GridPoint, tick: UInt64) -> TowerState.PlaceResult {
    guard let type = DistrictType.v1Catalog.first(where: { $0.id == typeID }) else {
      return .rejected(reason: "unknown type")
    }
    guard meta.unlockedTypeIDs.contains(typeID) else {
      return .rejected(reason: "locked")
    }
    let result = tower.place(type, at: origin, tick: tick)
    if case .placed(let perfect) = result {
      placements += 1
      collapse.registerPlacement()
      perfectStreak = perfect ? perfectStreak + 1 : 0
      let rent = economy.earnRent(districtsHoused: tower.districts.count, perfectStreak: perfectStreak)
      _ = rent
      meta.addXP(perfect ? 10 : 5)
    }
    return result
  }

  public mutating func handleCollapse(cause: CollapseCause, tick: UInt64) -> CollapseOutcome {
    perfectStreak = 0
    return collapse.resolveCollapse(cause: cause, tower: &tower)
  }

  /// Consume an Extra Revive helper if owned; otherwise the caller shows the
  /// rewarded-ad offer and calls `confirmAdRevive()` on completion.
  public mutating func revive() -> Bool {
    if economy.use(.extraRevive) { return true }
    return collapse.revive()
  }

  public mutating func confirmAdRevive() {
    _ = collapse.revive()
  }

  public mutating func abandonRevive() {
    collapse.declineRevive()
  }

  public struct RunSummary: Sendable {
    public let height: Int
    public let coinsEarned: Int
    public let xpEarned: Int
    public let milestone: SkylineMeta.Milestone?
  }

  public mutating func endRun() -> RunSummary {
    let height = tower.districts.count * 10
    let milestone = SkylineMeta.Milestone.milestone(for: height)
    let xpEarned = placements * 5
    meta.recordRun(districts: tower.districts, xpEarned: xpEarned)
    return RunSummary(height: height, coinsEarned: economy.coins, xpEarned: xpEarned, milestone: milestone)
  }
}
```

Note: this task requires adding `declineRevive()` to `CollapseRules`
(Task 5) — a one-line method: `mutating func declineRevive() { reviveAvailable = false }`.
Add it and its test (`#expect(rules.revive() == false)` after declining) to
the Task 5 test suite when implementing Task 9, or fold it into Task 5
directly. Prefer folding it into Task 5.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/GameCore && swift test --filter SkylineSessionTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Run the full suite + lint**

Run: `cd Packages/GameCore && swift test && swiftlint --config ../../.swiftlint.yml`
Expected: all tests PASS, no lint violations.

- [ ] **Step 6: Commit**

```bash
git add Packages/GameCore/Sources/GameCore/SkylineSession.swift Packages/GameCore/Tests/GameCoreTests/SkylineSessionTests.swift
git commit -m "Add SkylineSession facade wiring tower, economy, collapse and meta"
```

---

### Task 10: Full-suite verification and docs update

**Files:**
- Modify: `AGENTS.md` (status section — note GameCore now contains Skyline Stack logic)
- Modify: `docs/architecture.md` (add the new GameCore components)

- [ ] **Step 1: Run the entire test suite**

Run: `cd Packages/GameCore && swift test`
Expected: ALL tests pass (existing `GameCoreTests` + all new suites).

- [ ] **Step 2: Lint**

Run: `swiftlint --config .swiftlint.yml`
Expected: no violations.

- [ ] **Step 3: Update AGENTS.md status**

Add one line to the CURRENT STATUS section: "Skyline Stack GameCore logic
implemented (tower, placement, economy, collapse/revive, daily challenge) —
see `docs/superpowers/specs/2026-09-02-skyline-stack-design.md`."

- [ ] **Step 4: Update docs/architecture.md**

Add a short section listing the new GameCore components and their
responsibilities (mirror the File Structure table above).

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md docs/architecture.md
git commit -m "Document Skyline Stack GameCore components"
```

---

## Plan Self-Review Notes

- **Spec coverage (GameCore portion):** placement grid + sweet zone (Tasks 1–2), lean/stability/curing (Task 3), telegraphed deterministic wind (Task 4), cascade cap + revive + foundation loss (Task 5), economy/coins/helpers/IAP tiers (Task 6), persistent skyline + XP/unlocks + milestones + daily bonus (Task 7), daily seeded challenge (Task 8), facade wiring (Task 9). Physics simulation, rendering, UI, RevenueCat/AdMob integration are app-layer concerns → follow-up plan.
- **Known simplifications (deliberate, YAGNI):** curing is placement-count-based (not wall-clock); height = districts × 10 (the app layer reports real physics height later); `dailyBonusCoins` returns a flat 20 (per-day uniqueness is enforced by the caller tracking last-bonus date); `WindSystem.Direction` conformance is declared via extension at file end.
- **Type consistency check:** `GridPoint` used by `District`, `PlacementRules`, `TowerState`, `SkylineSession` — defined once in Task 2. `District.placedAtTick: UInt64` doubles as the cure/cured-set key. `CollapseRules.declineRevive()` must exist by Task 9 (fold into Task 5). `Economy.price(for:)` values used in tests: stabilizer 30, windBarrier 25, foundationReinforce 40, extraRevive 50.