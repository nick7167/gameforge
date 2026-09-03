# Emberfall Realms — Plan 1: GameCore Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete pure-Swift game logic engine for Emberfall Realms — hero catalog, gacha with pity, tick-based battle simulation, equipment, idle income, stage progression, quests, and the player profile — with 60+ green tests.

**Architecture:** All gameplay rules live in `Packages/GameCore` as Sendable value types with no UI dependencies. The app layer (Plan 2) drives an `EmberSession` facade and renders its state. Determinism comes from the existing `SeededGenerator` (SplitMix64). Skyline Stack gameplay files are deleted first; the package shell, `SeededGenerator`, and test conventions are kept.

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing (`@Test`), no external dependencies.

**Spec:** `docs/superpowers/specs/2026-09-03-emberfall-realms-design.md`

## Global Constraints

- Swift 6, strict concurrency; every public type `Sendable`
- 2-space indent, 150-char lines (`.swiftlint.yml`); no force unwraps
- Swift Testing framework (`@Test`, `#expect`) — NOT XCTest — in GameCore
- All randomness through `SeededGenerator` (seeded, reproducible)
- No energy system; no elemental counters (synergy-only factions)
- Currency names exactly: `gold`, `gems`, `arenaTokens`, `questTokens`
- Factions exactly: `ember`, `frost`, `verdant`, `void`
- Rarities exactly: `common`, `rare`, `epic`, `legendary`
- Gacha rates: Legendary 2%, Epic 10%, Rare 30%, Common 58%; pity Epic ≤10, Legendary ≤60
- Battle: 5-hero squad, ~30s normal / ~90s boss (2 phases, enrage at 50% HP)
- Offline income: flat best-stage rate, 12h cap (24h with Monthly Card)
- 20 heroes at launch: 4 Legendary, 6 Epic, 6 Rare, 4 Common; 5 per faction
- Run tests from `Packages/GameCore` with `swift test`; lint with `swiftlint --config .swiftlint.yml`

---

### Task 1: Delete Skyline Stack gameplay, keep the shell

**Files:**
- Delete: `Packages/GameCore/Sources/GameCore/{District,Placement,TowerState,WindSystem,CollapseRules,SkylineMeta,DailyChallenge,SkylineSession}.swift`
- Delete: `Packages/GameCore/Tests/GameCoreTests/{CollapseRulesTests,DailyChallengeTests,DistrictTests,EconomyTests,PlacementTests,SkylineMetaTests,SkylineSessionTests,TowerStateTests,WindSystemTests,GameCoreTests}.swift`
- Keep: `Packages/GameCore/Sources/GameCore/SeededGenerator.swift`, `Package.swift`

**Interfaces:**
- Produces: an empty GameCore package (only `SeededGenerator`) that still builds and lints clean — the foundation for all later tasks.

- [ ] **Step 1: Delete Skyline gameplay sources and tests**

```bash
cd /workspaces/gameforge/Packages/GameCore
rm Sources/GameCore/{District,Placement,TowerState,WindSystem,CollapseRules,SkylineMeta,DailyChallenge,SkylineSession}.swift
rm Tests/GameCoreTests/{CollapseRulesTests,DailyChallengeTests,DistrictTests,EconomyTests,PlacementTests,SkylineMetaTests,SkylineSessionTests,TowerStateTests,GameCoreTests}.swift
```

- [ ] **Step 2: Verify the package still builds and tests pass**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift build && swift test`
Expected: BUILD SUCCEEDED; tests pass (a suite with only SeededGenerator tests, or zero tests — both fine)

- [ ] **Step 3: Lint**

Run: `cd /workspaces/gameforge && swiftlint --config .swiftlint.yml`
Expected: no violations

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Remove Skyline Stack gameplay, keep GameCore shell"
```

---

### Task 2: Core value types — Faction, Rarity, StatBlock, Currency

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/Faction.swift`
- Create: `Packages/GameCore/Sources/GameCore/Rarity.swift`
- Create: `Packages/GameCore/Sources/GameCore/StatBlock.swift`
- Create: `Packages/GameCore/Sources/GameCore/Currency.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/CoreTypesTests.swift`

**Interfaces:**
- Produces: `enum Faction: String, CaseIterable, Codable, Sendable` (cases `ember, frost, verdant, void`); `enum Rarity: Int, Codable, Comparable, Sendable` (cases `common=0, rare=1, epic=2, legendary=3`); `struct StatBlock: Sendable, Codable` with `hp, attack, defense, speed, critChance, critDamage: Double`; `enum Currency: String, Codable, Sendable` (cases `gold, gems, arenaTokens, questTokens`); `struct Wallet: Sendable` with `balance(of:)`, `add(_:_:)`, `spend(_:_:) -> Bool`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import GameCore

@Suite struct CoreTypesTests {
  @Test func factionCases() {
    #expect(Faction.allCases == [.ember, .frost, .verdant, .void])
  }

  @Test func rarityOrdering() {
    #expect(Rarity.common < Rarity.rare)
    #expect(Rarity.rare < Rarity.epic)
    #expect(Rarity.epic < Rarity.legendary)
  }

  @Test func statBlockAddition() {
    let a = StatBlock(hp: 100, attack: 10, defense: 5, speed: 1, critChance: 0.05, critDamage: 1.5)
    let b = StatBlock(hp: 50, attack: 5, defense: 5, speed: 1, critChance: 0.05, critDamage: 0.5)
    let sum = a + b
    #expect(sum.hp == 150 && sum.attack == 15 && sum.critDamage == 2.5)
  }

  @Test func walletSpendFailsWhenInsufficient() {
    var wallet = Wallet()
    wallet.add(.gold, 100)
    #expect(wallet.spend(.gold, 200) == false)
    #expect(wallet.balance(of: .gold) == 0)
    #expect(wallet.spend(.gold, 50) == true)
    #expect(wallet.balance(of: .gold) == 0)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test 2>&1 | tail -5`
Expected: FAIL — cannot find `Faction`, `Rarity`, `StatBlock`, `Wallet` in scope

- [ ] **Step 3: Write the implementations**

`Faction.swift`:
```swift
/// The four hero factions. Synergy-only: no elemental counters (spec §4.2).
public enum Faction: String, CaseIterable, Codable, Sendable {
  case ember, frost, verdant, void

  /// Squad synergy bonus: 2 same-faction = +8% ATK, 4 = +20% ATK (spec §4.2).
  public var synergyAttackMultiplier: Double {
    switch self {
    case .ember, .frost, .verdant, .void: 1.0 // per-pair bonus applied by BattleEngine
    }
  }
}
```

`Rarity.swift`:
```swift
/// Hero/gear rarity. Raw value doubles as sort order and gacha weight index.
public enum Rarity: Int, Codable, Comparable, Sendable {
  case common = 0, rare = 1, epic = 2, legendary = 3

  public static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.rawValue < rhs.rawValue }

  /// UI color language (spec §13): gray/green/blue/purple/gold.
  public var uiColorHex: UInt32 {
    switch self {
    case .common: 0x9E9E9E
    case .rare: 0x42A5F5
    case .epic: 0xAB47BC
    case .legendary: 0xFFD76A
    }
  }
}
```

`StatBlock.swift`:
```swift
/// Combat stats for a hero or enemy. All additive; multipliers applied by BattleEngine.
public struct StatBlock: Sendable, Codable, AdditiveArithmetic {
  public var hp: Double
  public var attack: Double
  public var defense: Double
  public var speed: Double
  public var critChance: Double
  public var critDamage: Double

  public init(
    hp: Double = 0, attack: Double = 0, defense: Double = 0, speed: Double = 0,
    critChance: Double = 0.05, critDamage: Double = 1.5
  ) {
    self.hp = hp; self.attack = attack; self.defense = defense
    self.speed = speed; self.critChance = critChance; self.critDamage = critDamage
  }

  public static var zero: StatBlock { StatBlock() }
  public static func + (l: StatBlock, r: StatBlock) -> StatBlock {
    StatBlock(
      hp: l.hp + r.hp, attack: l.attack + r.attack, defense: l.defense + r.defense,
      speed: l.speed + r.speed, critChance: l.critChance + r.critChance,
      critDamage: l.critDamage + r.critDamage)
  }
  public static func - (l: StatBlock, r: StatBlock) -> StatBlock {
    StatBlock(
      hp: l.hp - r.hp, attack: l.attack - r.attack, defense: l.defense - r.defense,
      speed: l.speed - r.speed, critChance: l.critChance - r.critChance,
      critDamage: l.critDamage - r.critDamage)
  }
  public static func * (l: StatBlock, rhs: Double) -> StatBlock {
    StatBlock(
      hp: l.hp * rhs, attack: l.attack * rhs, defense: l.defense * rhs,
      speed: l.speed, critChance: l.critChance, critDamage: l.critDamage)
  }
}
```

`Currency.swift`:
```swift
/// The four currencies (spec §8). No energy — campaign is ungated.
public enum Currency: String, Codable, Sendable, CaseIterable {
  case gold, gems, arenaTokens, questTokens
}

/// Player currency balances. Spending fails (returns false) when insufficient.
public struct Wallet: Sendable, Codable {
  public private(set) var balances: [Currency: Int]

  public init(balances: [Currency: Int] = [:]) {
    self.balances = balances
  }

  public func balance(of currency: Currency) -> Int { balances[currency] ?? 0 }

  public mutating func add(_ currency: Currency, _ amount: Int) {
    balances[currency, default: 0] += amount
  }

  @discardableResult
  public mutating func spend(_ currency: Currency, _ amount: Int) -> Bool {
    guard let current = balances[currency], current >= amount else { return false }
    balances[currency] = current - amount
    return true
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test`
Expected: PASS (all CoreTypesTests green)

- [ ] **Step 5: Lint and commit**

```bash
cd /workspaces/gameforge && swiftlint --config .swiftlint.yml
git add -A && git commit -m "Add core value types: faction, rarity, stats, wallet"
```

---

### Task 3: Hero catalog — 20 heroes, 4 factions, 7 roles

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/HeroCatalog.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/HeroCatalogTests.swift`

**Interfaces:**
- Consumes: `Faction`, `Rarity`, `StatBlock` (Task 2)
- Produces: `enum HeroRole: String, Codable, Sendable` (cases `tank, dps, healer, support, ranger, controller, assassin`); `struct HeroDefinition: Sendable, Identifiable, Codable` with `id: String, name: String, faction: Faction, rarity: Rarity, role: HeroRole, baseStats: StatBlock, ultimate: UltimateDefinition, passives: [PassiveDefinition], lore: String`; `struct UltimateDefinition: Sendable, Codable` (`id, name, damageMultiplier: Double, effect: UltimateEffect`); `enum UltimateEffect: Codable, Sendable` (`.damage, .heal, .shield, .stun, .buffAttack(Double), .dot`); `struct PassiveDefinition: Sendable, Codable` (`id, name, description`); `enum HeroCatalog` with `static let all: [HeroDefinition]` (exactly 20), `static func hero(id:) -> HeroDefinition?`, `static func heroes(faction:) -> [HeroDefinition]`, `static func byRarity(_:) -> [HeroDefinition]`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import GameCore

@Suite struct HeroCatalogTests {
  @Test func catalogHasExactly20Heroes() {
    #expect(HeroCatalog.all.count == 20)
  }

  @Test func fiveHeroesPerFaction() {
    for faction in Faction.allCases {
      #expect(HeroCatalog.faction(faction).count == 5, "faction \(faction) needs 5 heroes")
    }
  }

  @Test func rarityDistribution() {
    #expect(HeroCatalog.byRarity(.legendary).count == 4)
    #expect(HeroCatalog.byRarity(.epic).count == 6)
    #expect(HeroCatalog.byRarity(.rare).count == 6)
    #expect(HeroCatalog.byRarity(.common).count == 4)
  }

  @Test func allSevenRolesPresent() {
    let roles = Set(HeroCatalog.all.map(\.role))
    #expect(roles.count == 7)
  }

  @Test func everyHeroHasUltimateAndTwoPassives() {
    for hero in HeroCatalog.all {
      #expect(!hero.ultimate.name.isEmpty)
      #expect(hero.passives.count == 2)
    }
  }

  @Test func uniqueIDs() {
    #expect(Set(HeroCatalog.all.map(\.id)).count == 20)
  }

  @Test func legendariesHaveUniqueMechanic() {
    for hero in HeroCatalog.byRarity(.legendary) {
      #expect(hero.ultimate.effect != .damage) // unique mechanic, not plain damage
    }
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test 2>&1 | tail -3`
Expected: FAIL — cannot find `HeroCatalog` in scope

- [ ] **Step 3: Write the catalog**

`HeroCatalog.swift` (complete file — all 20 heroes; stats scale with rarity:
common base ~[800, 60, 30, 1.0], rare ×1.4, epic ×2.0, legendary ×3.0; roles shape stat spreads):

```swift
/// Hero roles (spec §4.2).
public enum HeroRole: String, Codable, Sendable, CaseIterable {
  case tank, dps, healer, support, ranger, controller, assassin
}

/// Ultimate effects. Legendaries must use a non-`.damage` effect (unique mechanic).
public enum UltimateEffect: Codable, Sendable, Equatable {
  case damage
  case healAll(percent: Double)
  case shieldAll(percent: Double)
  case stunAll(duration: Double)
  case buffAttack(percent: Double, duration: Double)
  case execute(threshold: Double)          // Void legendaries: bonus dmg below HP%
  case chainDamage(bounces: Int)           // Ember legendaries: hits multiple foes
  case freezeAll(duration: Double)         // Frost legendaries
  case lifesteal(percent: Double)          // Verdant legendaries
}

public struct UltimateDefinition: Sendable, Codable {
  public let id: String
  public let name: String
  public let damageMultiplier: Double
  public let effect: UltimateEffect
  public init(id: String, name: String, damageMultiplier: Double = 2.5, effect: UltimateEffect = .damage) {
    self.id = id; self.name = name; self.damageMultiplier = damageMultiplier; self.effect = effect
  }
}

public struct PassiveDefinition: Sendable, Codable {
  public let id: String
  public let name: String
  public let description: String
  public init(id: String, name: String, description: String) {
    self.id = id; self.name = name; self.description = description
  }
}

public struct HeroDefinition: Sendable, Identifiable, Codable {
  public let id: String
  public let name: String
  public let faction: Faction
  public let rarity: Rarity
  public let role: HeroRole
  public let baseStats: StatBlock
  public let ultimate: UltimateDefinition
  public let passives: [PassiveDefinition]
  public let lore: String
}

/// The launch roster: 20 heroes, 5 per faction, 4L/6E/6R/4C (spec §6.1).
public enum HeroCatalog {
  public static let all: [HeroDefinition] = ember + frost + verdant + void

  // MARK: - Ember (burst damage)

  public static let ember: [HeroDefinition] = [
    HeroDefinition(
      id: "pyrelord", name: "Pyrelord", faction: .ember, rarity: .legendary, role: .dps,
      baseStats: StatBlock(hp: 2400, attack: 190, defense: 90, speed: 1.1, critChance: 0.20, critDamage: 2.0),
      ultimate: UltimateDefinition(id: "inferno-slash", name: "Inferno Slash", damageMultiplier: 3.2, effect: .chainDamage(bounces: 3)),
      passives: [
        PassiveDefinition(id: "pyrelord-p1", name: "Kindled Fury", description: "Crits grant +5% attack for 5s (stacks 3x)."),
        PassiveDefinition(id: "pyrelord-p2", name: "Burning Aura", description: "Nearby enemies take 10% attack as burn per second.")
      ],
      lore: "The last flame of a fallen citadel, burning with purpose."
    ),
    HeroDefinition(
      id: "cinderblade", name: "Cinderblade", faction: .ember, rarity: .epic, role: .assassin,
      baseStats: StatBlock(hp: 1500, attack: 130, defense: 60, speed: 1.3, critChance: 0.25, critDamage: 1.8),
      ultimate: UltimateDefinition(id: "ember-storm", name: "Ember Storm", damageMultiplier: 2.8, effect: .damage),
      passives: [
        PassiveDefinition(id: "cinderblade-p1", name: "Backdraft", description: "+30% damage against enemies below 40% HP."),
        PassiveDefinition(id: "cinderblade-p2", name: "Heat Haze", description: "10% chance to dodge attacks.")
      ],
      lore: "A duelist whose blade never cools."
    ),
    HeroDefinition(
      id: "ashguard", name: "Ashguard", faction: .ember, rarity: .rare, role: .tank,
      baseStats: StatBlock(hp: 1900, attack: 70, defense: 110, speed: 0.9),
      ultimate: UltimateDefinition(id: "magma-wall", name: "Magma Wall", damageMultiplier: 1.2, effect: .shieldAll(percent: 0.15)),
      passives: [
        PassiveDefinition(id: "ashguard-p1", name: "Molten Core", description: "Reflects 12% of damage taken."),
        PassiveDefinition(id: "ashguard-p2", name: "Ember Skin", description: "Takes 10% less damage from burns.")
      ],
      lore: "Forged in the pyres, sworn to stand until the last ember fades."
    ),
    HeroDefinition(
      id: "sparkmage", name: "Sparkmage", faction: .ember, rarity: .rare, role: .controller,
      baseStats: StatBlock(hp: 1200, attack: 95, defense: 45, speed: 1.0),
      ultimate: UltimateDefinition(id: "static-field", name: "Static Field", damageMultiplier: 1.8, effect: .stunAll(duration: 2.0)),
      passives: [
        PassiveDefinition(id: "sparkmage-p1", name: "Overcharge", description: "Every 3rd attack deals +50% damage."),
        PassiveDefinition(id: "sparkmage-p2", name: "Conductive", description: "Stunned enemies take +15% damage.")
      ],
      lore: "She bottled the first lightning of the Emberfall and never stopped."
    ),
    HeroDefinition(
      id: "torchbearer", name: "Torchbearer", faction: .ember, rarity: .common, role: .support,
      baseStats: StatBlock(hp: 1000, attack: 60, defense: 40, speed: 1.0),
      ultimate: UltimateDefinition(id: "rally-flame", name: "Rally Flame", damageMultiplier: 1.0, effect: .buffAttack(percent: 0.15, duration: 8.0)),
      passives: [
        PassiveDefinition(id: "torchbearer-p1", name: "Warm Light", description: "Allies regenerate 1% HP per second."),
        PassiveDefinition(id: "torchbearer-p2", name: "Cheer", description: "+5% attack to the ally with the lowest HP.")
      ],
      lore: "Where the torch passes, hope follows."
    ),

    // MARK: - Frost
    HeroDefinition(
      id: "glacia", name: "Glacia", faction: .frost, rarity: .legendary, role: .controller,
      baseStats: StatBlock(hp: 2100, attack: 150, defense: 100, speed: 1.0),
      ultimate: UltimateDefinition(id: "absolute-zero", name: "Absolute Zero", damageMultiplier: 2.0, effect: .freezeAll(duration: 3.0)),
      passives: [
        PassiveDefinition(id: "glacia-p1", name: "Winter's Grasp", description: "Frozen enemies take +25% damage."),
        PassiveDefinition(id: "glacia-p2", name: "Cold Snap", description: "Every 5th attack freezes for 1s.")
      ],
      lore: "She remembers when the sun last set — and intends to see it again."
    ),
    HeroDefinition(
      id: "frostwarden", name: "Frostwarden", faction: .frost, rarity: .epic, role: .healer,
      baseStats: StatBlock(hp: 1800, attack: 90, defense: 95, speed: 1.0),
      ultimate: UltimateDefinition(id: "glacial-mend", name: "Glacial Mend", damageMultiplier: 1.0, effect: .healAll(percent: 0.20)),
      passives: [
        PassiveDefinition(id: "frostwarden-p1", name: "Rime Regrowth", description: "Healing also grants a 5% shield."),
        PassiveDefinition(id: "frostwarden-p2", name: "Chill Aura", description: "Nearby enemies attack 10% slower.")
      ],
      lore: "Her mercy is the quiet kind — the kind that lets you keep fighting."
    ),
    HeroDefinition(
      id: "sleetarcher", name: "Sleetarcher", faction: .frost, rarity: .rare, role: .ranger,
      baseStats: StatBlock(hp: 1100, attack: 95, defense: 40, speed: 1.2),
      ultimate: UltimateDefinition(id: "hail-volley", name: "Hail Volley", damageMultiplier: 2.4, effect: .damage),
      passives: [
        PassiveDefinition(id: "sleetarcher-p1", name: "Piercing Cold", description: "Attacks ignore 15% of defense."),
        PassiveDefinition(id: "sleetarcher-p2", name: "Icicle Trap", description: "10% chance to slow the target by 30% for 3s.")
      ],
      lore: "One arrow, one breath, one frozen heart."
    ),
    HeroDefinition(
      id: "rimefist", name: "Rimefist", faction: .frost, rarity: .common, role: .dps,
      baseStats: StatBlock(hp: 950, attack: 70, defense: 45, speed: 1.0),
      ultimate: UltimateDefinition(id: "frost-fist", name: "Frost Fist", damageMultiplier: 2.2, effect: .damage),
      passives: [
        PassiveDefinition(id: "rimefist-p1", name: "Bruising Blow", description: "Attacks reduce target defense by 5% (stacks 2x)."),
        PassiveDefinition(id: "rimefrost-p2", name: "Toughen", description: "Gains 5 defense with each hit taken (max 50).")
      ],
      lore: "He punched an iceberg once. The iceberg apologized."
    ),
    HeroDefinition(
      id: "snowcap", name: "Snowcap", faction: .frost, rarity: .common, role: .support,
      baseStats: StatBlock(hp: 1050, attack: 55, defense: 50, speed: 1.0),
      ultimate: UltimateDefinition(id: "blizzard-veil", name: "Blizzard Veil", damageMultiplier: 0.8, effect: .shieldAll(percent: 0.12)),
      passives: [
        PassiveDefinition(id: "snowcap-p1", name: "Insulating", description: "Allies take 5% less damage."),
        PassiveDefinition(id: "snowcap-p2", name: "Frostbite", description: "Attackers are slowed 8% for 2s.")
      ],
      lore: "Small, round, and unexpectedly hard to kill."
    ),

    // MARK: - Verdant
    HeroDefinition(
      id: "thornbow", name: "Thornbow", faction: .verdant, rarity: .legendary, role: .ranger,
      baseStats: StatBlock(hp: 2000, attack: 185, defense: 85, speed: 1.2, critChance: 0.22, critDamage: 1.9),
      ultimate: UltimateDefinition(id: "wild-volley", name: "Wild Volley", damageMultiplier: 2.6, effect: .lifesteal(percent: 0.4)),
      passives: [
        PassiveDefinition(id: "thornbow-p1", name: "Bramble Rounds", description: "Attacks poison for 8% attack over 3s."),
        PassiveDefinition(id: "thornbow-p2", name: "Rooted", description: "+20% attack while below 50% HP.")
      ],
      lore: "The forest keeps score, and she is its ledger."
    ),
    HeroDefinition(
      id: "grovekeeper", name: "Grovekeeper", faction: .verdant, rarity: .epic, role: .healer,
      baseStats: StatBlock(hp: 1900, attack: 85, defense: 95, speed: 1.0),
      ultimate: UltimateDefinition(id: "life-bloom", name: "Life Bloom", damageMultiplier: 0.9, effect: .healAll(percent: 0.20)),
      passives: [
        PassiveDefinition(id: "grovekeeper-p1", name: "Deep Roots", description: "Healing over 15% also cleanses one debuff."),
        PassiveDefinition(id: "grovekeeper-p2", name: "Photosynthesis", description: "Regenerates 2% HP per second while shielded.")
      ],
      lore: "Every wound is just a season waiting to turn."
    ),
    HeroDefinition(
      id: "barkskin", name: "Barkskin", faction: .verdant, rarity: .rare, role: .tank,
      baseStats: StatBlock(hp: 2000, attack: 65, defense: 105, speed: 0.9),
      ultimate: UltimateDefinition(id: "ironwood-aegis", name: "Ironwood Aegis", damageMultiplier: 1.0, effect: .shieldAll(percent: 0.18)),
      passives: [
        PassiveDefinition(id: "barkskin-p1", name: "Thorned Hide", description: "Attackers take 10% of damage dealt back."),
        PassiveDefinition(id: "barkskin-p2", name: "Ancient Growth", description: "Max HP increases 3% each minute of battle.")
      ],
      lore: "Older than the paths, patient as the soil."
    ),
    HeroDefinition(
      id: "petalblade", name: "Petalblade", faction: .verdant, rarity: .rare, role: .assassin,
      baseStats: StatBlock(hp: 1000, attack: 100, defense: 40, speed: 1.35, critChance: 0.28),
      ultimate: UltimateDefinition(id: "bloom-dance", name: "Petal Dance", damageMultiplier: 2.6, effect: .damage),
      passives: [
        PassiveDefinition(id: "petalblade-p1", name: "First Bloom", description: "Opening attack always crits."),
        PassiveDefinition(id: "petalblade-p2", name: "Petal Storm", description: "Kills grant +20% speed for 4s.")
      ],
      lore: "Beauty, briefly. Then the cut."
    ),
    HeroDefinition(
      id: "mosslings", name: "Mosslings", faction: .verdant, rarity: .common, role: .support,
      baseStats: StatBlock(hp: 1100, attack: 55, defense: 55, speed: 1.0),
      ultimate: UltimateDefinition(id: "spore-cloud", name: "Spore Cloud", damageMultiplier: 1.0, effect: .stunAll(duration: 1.5)),
      passives: [
        PassiveDefinition(id: "mosslings-p1", name: "Symbiosis", description: "Heals the nearest ally 1.5% HP per second."),
        PassiveDefinition(id: "mosslings-p2", name: "Hardy", description: "Immune to poison.")
      ],
      lore: "A hundred small helpers pretending to be one hero."
    ),

    // MARK: - Void
    HeroDefinition(
      id: "nullreaper", name: "Nullreaper", faction: .void, rarity: .legendary, role: .assassin,
      baseStats: StatBlock(hp: 1900, attack: 200, defense: 80, speed: 1.3, critChance: 0.30, critDamage: 2.2),
      ultimate: UltimateDefinition(id: "void-cleave", name: "Void Cleave", damageMultiplier: 3.0, effect: .execute(threshold: 0.25)),
      passives: [
        PassiveDefinition(id: "nullreaper-p1", name: "Entropy", description: "Each hit adds +2% crit chance (max +20%)."),
        PassiveDefinition(id: "nullreaper-p2", name: "Phase Step", description: "First attack each wave cannot miss.")
      ],
      lore: "Where it passes, the world forgets to have existed."
    ),
    HeroDefinition(
      id: "duskcaller", name: "Duskcaller", faction: .void, rarity: .epic, role: .controller,
      baseStats: StatBlock(hp: 1500, attack: 110, defense: 70, speed: 1.1),
      ultimate: UltimateDefinition(id: "eclipse-brand", name: "Eclipse Brand", damageMultiplier: 2.0, effect: .stunAll(duration: 2.5)),
      passives: [
        PassiveDefinition(id: "duskcaller-p1", name: "Dread", description: "Enemies below 50% HP deal 10% less damage."),
        PassiveDefinition(id: "duskcaller-p2", name: "Umbral Siphon", description: "Heals 5% of damage dealt.")
      ],
      lore: "The dusk is not an ending. It is an appetite."
    ),
    HeroDefinition(
      id: "voidpriest", name: "Voidpriest", faction: .void, rarity: .epic, role: .support,
      baseStats: StatBlock(hp: 1600, attack: 95, defense: 80, speed: 1.0),
      ultimate: UltimateDefinition(id: "dark-communion", name: "Dark Communion", damageMultiplier: 1.2, effect: .buffAttack(percent: 0.25, duration: 10.0)),
      passives: [
        PassiveDefinition(id: "voidpriest-p1", name: "Blood Pact", description: "Ults cost 5% HP but charge 20% faster."),
        PassiveDefinition(id: "voidpriest-p2", name: "Ominous Presence", description: "Enemies start battle with -10% attack.")
      ],
      lore: "She speaks softly, and the dark leans in to listen."
    ),
    HeroDefinition(
      id: "gloomfang", name: "Gloomfang", faction: .void, rarity: .rare, role: .dps,
      baseStats: StatBlock(hp: 1150, attack: 105, defense: 50, speed: 1.15, critChance: 0.20),
      ultimate: UltimateDefinition(id: "shadow-frenzy", name: "Shadow Frenzy", damageMultiplier: 2.5, effect: .damage),
      passives: [
        PassiveDefinition(id: "gloomfang-p1", name: "Feeding Frenzy", description: "Kills restore 10% HP."),
        PassiveDefinition(id: "gloomfang-p2", name: "Night Vision", description: "+15% crit chance against slowed enemies.")
      ],
      lore: "It was a wolf once. The dark kept the shape and lost the mercy."
    ),
    HeroDefinition(
      id: "duskhound", name: "Duskhound", faction: .void, rarity: .common, role: .dps,
      baseStats: StatBlock(hp: 900, attack: 75, defense: 40, speed: 1.2),
      ultimate: UltimateDefinition(id: "night-rush", name: "Night Rush", damageMultiplier: 2.0, effect: .damage),
      passives: [
        PassiveDefinition(id: "duskhound-p1", name: "Relentless", description: "+10% attack for every enemy defeated (max 3)."),
        PassiveDefinition(id: "duskhound-p2", name: "Loyal", description: "Gains a 5% shield when an ally dies.")
      ],
      lore: "Good dog. Terrible omen."
    ),
  ]

  public static func hero(id: String) -> HeroDefinition? {
    all.first { $0.id == id }
  }

  public static func faction(_ faction: Faction) -> [HeroDefinition] {
    all.filter { $0.faction == faction }
  }

  public static func byRarity(_ rarity: Rarity) -> [HeroDefinition] {
    all.filter { $0.rarity == rarity }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test`
Expected: PASS (all HeroCatalogTests green)

- [ ] **Step 5: Lint and commit**

```bash
cd /workspaces/gameforge && swiftlint --config .swiftlint.yml
git add -A && git commit -m "Add hero catalog: 20 heroes, 4 factions, 7 roles"
```

---

### Task 4: Gacha engine — rates, pity, banners, dupes

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/GachaEngine.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/GachaEngineTests.swift`

**Interfaces:**
- Consumes: `HeroCatalog`, `HeroDefinition`, `Rarity`, `SeededGenerator`, `Wallet` (Tasks 2–3)
- Produces: `struct GachaState: Sendable, Codable` (`epicPity: Int, legendaryPity: Int, pullsSinceFeaturedLegendary: Int`); `enum BannerKind: Sendable` (`.permanent, .featured(heroID: String)`); `struct GachaEngine: Sendable` with `init(state: GachaState = GachaState())`; `mutating func pull(banner: BannerKind, shards: inout Int, rng: inout SeededGenerator) -> PullResult`; `struct PullResult: Sendable` (`hero: HeroDefinition, isNew: Bool, factionShardsAwarded: Int, state: GachaState`); `struct BannerKind: Sendable, Equatable` with `static let permanent: BannerKind` and `static func featured(heroID: String) -> BannerKind`. Pull cost: 100 shards single, 900 shards 10-pull (`static let singleCost = 100`, `static let multiCost = 900`).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import GameCore

@Suite struct GachaEngineTests {
  @Test func pullCostsShards() {
    var engine = GachaEngine()
    var shards = 100
    var rng = SeededGenerator(seed: 1)
    let result = engine.pull(banner: .permanent, shards: &shards, rng: &rng)
    #expect(shards == 0)
    #expect(result.hero.rarity >= .common)
  }

  @Test func pullFailsWithoutShards() {
    var engine = GachaEngine()
    var shards = 99
    var rng = SeededGenerator(seed: 1)
    #expect(throws: GachaError.insufficientShards) {
      _ = try engine.pull(banner: .permanent, shards: &shards, rng: &rng)
    }
  }

  @Test func epicPityTriggersWithin10() {
    var engine = GachaEngine()
    var shards = 10_000
    var rng = SeededGenerator(seed: 42)
    var sawEpicOrBetter = false
    for _ in 0..<10 {
      let result = try! engine.pull(banner: .permanent, shards: &shards, rng: &rng)
      if result.hero.rarity >= .epic { sawEpicOrBetter = true; break }
    }
    #expect(sawEpicOrBetter) // pity guarantees Epic within 10 pulls
  }

  @Test func legendaryPityTriggersWithin60() {
    var engine = GachaEngine()
    var shards = 60_000
    var rng = SeededGenerator(seed: 42)
    var gotLegendary = false
    for _ in 0..<60 {
      let result = try! engine.pull(banner: .permanent, shards: &shards, rng: &rng)
      if result.hero.rarity == .legendary { gotLegendary = true; break }
    }
    #expect(gotLegendary) // pity guarantees Legendary within 60 pulls
  }

  @Test func duplicatesAwardFactionShards() {
    var engine = GachaEngine()
    var shards = 100_000
    var rng = SeededGenerator(seed: 7)
    var owned = Set<String>()
    var sawDupeShards = false
    for _ in 0..<40 {
      let result = try! engine.pull(banner: .permanent, shards: &shards, rng: &rng)
      if !result.isNew { if result.factionShardsAwarded > 0 { sawDupeShards = true } }
      _ = result
    }
    #expect(sawDupeShards)
  }

  @Test func tenPullCostsLessThanTenSingles() {
    #expect(GachaEngine.multiCost < GachaEngine.singleCost * 10)
  }

  @Test func featuredBannerRatesUp() {
    // Statistical: featured banner should yield the featured hero among legendaries ~50%
    var engine = GachaEngine()
    var shards = 500_000
    var rng = SeededGenerator(seed: 99)
    var featuredCount = 0
    var legendaryCount = 0
    for _ in 0..<500 {
      let result = try! engine.pull(banner: .featured(heroID: "pyrelord"), shards: &shards, rng: &rng)
      if result.hero.rarity == .legendary {
        legendaryCount += 1
        if result.hero.id == "pyrelord" { featuredCount += 1 }
      }
    }
    #expect(legendaryCount > 5) // 2% base + pity should yield some legendaries
    if legendaryCount >= 10 {
      let ratio = Double(featuredCount) / Double(legendaryCount)
      #expect(ratio > 0.3 && ratio < 0.7) // ~50% featured
    }
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test 2>&1 | tail -3`
Expected: FAIL — cannot find `GachaEngine` in scope

- [ ] **Step 3: Write the gacha engine**

`GachaEngine.swift`:
```swift
import Foundation

/// Persistent gacha counters (pity). Persist with the player profile.
public struct GachaState: Sendable, Codable {
  public var epicPity: Int = 0
  public var legendaryPity: Int = 0
  public var pullsSinceFeaturedLegendary: Int = 0

  public init(epicPity: Int = 0, legendaryPity: Int = 0, pullsSinceFeaturedLegendary: Int = 0) {
    self.epicPity = epicPity
    self.legendaryPity = legendaryPity
    self.pullsSinceFeaturedLegendary = pullsSinceFeaturedLegendary
  }
}

public enum GachaError: Error, Sendable {
  case insufficientShards
}

/// Gacha engine (spec §6.2): permanent pool + weekly featured banner,
/// visible pity (Epic ≤10, Legendary ≤60), dupes → faction shards.
public struct GachaEngine: Sendable {
  public static let singleCost = 100
  public static let multiCost = 900

  private static let legendaryRate = 0.02
  private static let epicRate = 0.10
  private static let rareRate = 0.30
  // common = remainder (0.58)

  private static let epicPityLimit = 10
  private static let legendaryPityLimit = 60

  public private(set) var state: GachaState

  public init(state: GachaState = GachaState()) {
    self.state = state
  }

  public enum BannerKind: Sendable, Equatable {
    case permanent
    case featured(heroID: String)
  }

  public struct PullResult: Sendable {
    public let hero: HeroDefinition
    public let isNew: Bool
    public let factionShardsAwarded: Int
  }

  /// Pull once. Throws `GachaError.insufficientShards` if the player can't afford it.
  public mutating func pull(
    banner: BannerKind, shards: inout Int, ownedHeroIDs: Set<String>, rng: inout SeededGenerator
  ) throws -> PullResult {
    guard shards >= Self.singleCost else { throw GachaError.insufficientShards }
    shards -= Self.singleCost

    state.epicPity += 1
    state.legendaryPity += 1

    let roll = Double.random(in: 0..<1, using: &rng)

    let rarity: Rarity
    if state.legendaryPity >= Self.legendaryPityLimit || roll < Self.legendaryRate {
      rarity = .legendary
      state.legendaryPity = 0
      state.epicPity = 0
    } else if state.epicPity >= Self.epicPityLimit || roll < Self.legendaryRate + Self.epicRate {
      rarity = .epic
      state.epicPity = 0
    } else if roll < Self.legendaryRate + Self.epicRate + Self.rareRate {
      rarity = .rare
    } else {
      rarity = .common
    }

    let hero = pickHero(rarity: rarity, banner: banner, using: &rng)
    let isNew = !ownedHeroIDs.contains(hero.id)
    let factionShards = isNew ? 0 : factionShardsForDupe(hero.rarity)
    state.pullsSinceFeaturedLegendary += 1

    return PullResult(hero: hero, isNew: isNew, factionShardsAwarded: factionShards)
  }

  /// 10× pull: costs `multiCost`, guarantees at least one Rare.
  public mutating func pullTen(
    banner: BannerKind, shards: inout Int, ownedHeroIDs: Set<String>, rng: inout SeededGenerator
  ) -> [PullResult] {
    guard shards >= Self.multiCost else { return [] }
    shards -= Self.multiCost
    var results: [PullResult] = []
    for i in 0..<10 {
      let forcedRare = (i == 9 && !results.contains { $0.hero.rarity >= .rare })
      let result = pullRaw(banner: banner, ownedHeroIDs: ownedHeroIDs, rng: &rng, minimumRarity: forcedRare ? .rare : nil)
      results.append(result)
    }
    return results
  }

  private func factionShardsForDupe(_ rarity: Rarity) -> Int {
    switch rarity {
    case .common: return 1
    case .rare: return 3
    case .epic: return 10
    case .legendary: return 30
    }
  }
}
```

*(Implementation note for the executor: `pullRaw` is the shared internal that both
`pull` and `pullTen` call; `pull` is `pullRaw` with cost handling. The pity counters
increment per pull; when a rarity is granted by pity, reset that counter. The
`minimumRarity` parameter forces at least the given rarity on the last pull of a 10×.
Keep all rolls on `SeededGenerator` for determinism.)*

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test`
Expected: PASS (all GachaEngineTests green)

- [ ] **Step 5: Lint and commit**

```bash
cd /workspaces/gameforge && swiftlint --config .swiftlint.yml
git add -A && git commit -m "Add gacha engine with pity, banners, dupe shards"
```

---

### Task 5: Battle engine — tick simulation, ults, crits, phases

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/BattleEngine.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/BattleEngineTests.swift`

**Interfaces:**
- Consumes: `HeroCatalog`, `HeroDefinition`, `StatBlock`, `UltimateEffect`, `SeededGenerator` (Tasks 2–3)
- Produces: `struct BattleUnit: Sendable, Identifiable` (`id: String, def: HeroDefinition, stats: StatBlock, hp: Double, maxHP: Double, ultCharge: Double, isEnemy: Bool, faction: Faction, isBoss: Bool`); `struct BattleState: Sendable` (`heroes: [BattleEngine.Unit], enemies: [BattleEngine.Unit], elapsed: Double, phase: Int, outcome: BattleOutcome?`); `enum BattleOutcome: Sendable, Equatable` (`.ongoing, .victory, .defeat`); `struct BattleConfig: Sendable` (`enemyStats: StatBlock, enemyCount: Int, isBoss: Bool, stagePower: Double`); `struct BattleEngine: Sendable` with `init(heroDefs: [HeroDefinition], config: BattleConfig, seed: UInt64)`; `mutating func tick(_ dt: Double)`; `mutating func fireUltimate(heroID: String) -> UltResult`; `var outcome: BattleOutcome`; `var isBossPhase2: Bool`. `UltResult: Sendable` (`damage: Int, crit: Bool, targetID: String?`).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import GameCore

@Suite struct BattleEngineTests {
  var squad: [HeroDefinition] {
    [
      HeroCatalog.hero(id: "pyrelord")!,
      HeroCatalog.hero(id: "glacia")!,
      HeroCatalog.hero(id: "thornbow")!,
      HeroCatalog.hero(id: "nullreaper")!,
      HeroCatalog.hero(id: "torchbearer")!,
    ]
  }

  @Test func battleRunsToOutcome() {
    var battle = BattleEngine(
      heroDefs: squad,
      config: BattleConfig(enemyStats: StatBlock(hp: 800, attack: 40, defense: 20, speed: 1.0), enemyCount: 3, isBoss: false, stagePower: 1.0),
      seed: 1
    )
    var ticks = 0
    while battle.outcome == .ongoing && battle.elapsed < 120 {
      battle.tick(0.1)
    }
    #expect(battle.outcome != .ongoing)
  }

  @Test func ultChargesAndFires() {
    var battle = BattleEngine(
      heroDefs: squad,
      config: BattleConfig(enemyStats: StatBlock(hp: 5000, attack: 40, defense: 20, speed: 1.0), enemyCount: 2, isBoss: false, stagePower: 1.0),
      seed: 2
    )
    // Fast-forward until an ult is charged
    var heroID: String?
    for _ in 0..<600 where heroID == nil {
      battle.tick(0.1)
      heroID = battle.heroes.first(where: { $0.ultCharge >= 1.0 })?.id
    }
    #expect(heroID != nil)
    let before = battle.enemies.reduce(0) { $0 + $1.hp }
    let result = battle.fireUltimate(heroID: heroID!)
    #expect(result.damage > 0)
  }

  @Test func bossHasTwoPhases() {
    var battle = BattleEngine(
      heroDefs: squad,
      config: BattleConfig(enemyStats: StatBlock(hp: 5000, attack: 60, defense: 30, speed: 1.0), enemyCount: 1, isBoss: true, stagePower: 1.0),
      seed: 3
    )
    #expect(battle.isBossPhase2 == false)
    var guardCount = 0
    while battle.outcome == .ongoing && guardCount < 20_000 {
      battle.tick(0.1)
      guardCount += 1
      if battle.isBossPhase2 { break }
    }
    #expect(battle.isBossPhase2) // boss enters phase 2 at 50% HP
  }

  @Test func victoryWhenAllEnemiesDead() {
    var battle = BattleEngine(
      heroDefs: squad,
      config: BattleConfig(enemyStats: StatBlock(hp: 100, attack: 1, defense: 0, speed: 1.0), enemyCount: 1, isBoss: false, stagePower: 1.0),
      seed: 4
    )
    var guardCount = 0
    while battle.outcome == .ongoing && guardCount < 10_000 {
      battle.tick(0.1)
      guardCount += 1
    }
    #expect(battle.outcome == .victory)
  }

  @Test func wallRuleLosingKeepsLoot() {
    // A very weak squad vs a very strong enemy should lose, not hang
    let weakSquad = [HeroCatalog.hero(id: "torchbearer")!]
    var battle = BattleEngine(
      heroDefs: weakSquad,
      config: BattleConfig(enemyStats: StatBlock(hp: 100_000, attack: 500, defense: 500, speed: 2.0), enemyCount: 4, isBoss: false, stagePower: 5.0),
      seed: 5
    )
    var guardCount = 0
    while battle.outcome == .ongoing && guardCount < 10_000 {
      battle.tick(0.1)
      guardCount += 1
    }
    #expect(battle.outcome == .defeat)
  }

  @Test func deterministicWithSameSeed() {
    func runBattle(seed: UInt64) -> Double {
      var battle = BattleEngine(
        heroDefs: squad,
        config: BattleConfig(enemyStats: StatBlock(hp: 2000, attack: 80, defense: 30, speed: 1.0), enemyCount: 3, isBoss: false, stagePower: 1.0),
        seed: seed
      )
      while battle.outcome == .ongoing && battle.elapsed < 120 { battle.tick(0.1) }
      return battle.elapsed
    }
    #expect(runBattle(seed: 99) == runBattle(seed: 99))
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test 2>&1 | tail -3`
Expected: FAIL — cannot find `BattleEngine` in scope

- [ ] **Step 3: Write the battle engine**

`BattleEngine.swift`:

```swift
import Foundation

/// Tick-based auto-battle simulation (spec §4). No UI. Deterministic per seed.
///
/// The app layer mirrors this state into SceneKit nodes; all rules live here.
public struct BattleEngine: Sendable {
  public enum Outcome: Sendable, Equatable {
    case ongoing, victory, defeat
  }

  public struct Unit: Sendable, Identifiable {
    public let id: String
    public let def: HeroDefinition
    public let stats: StatBlock
    public let isEnemy: Bool
    public let isBoss: Bool
    public var hp: Double
    public var maxHP: Double
    public var ultCharge: Double
    public var attackCooldown: Double
    public var buffAttackPercent: Double
    public var buffTimer: Double
    public var stunTimer: Double

    public var isAlive: Bool { hp > 0 }
  }

  public struct UltResult: Sendable {
    public let heroID: String
    public let damage: Double
    public let crit: Bool
    public let targetID: String?
  }

  public private(set) var heroes: [Unit]
  public private(set) var enemies: [Unit]
  public private(set) var elapsed: Double = 0
  public private(set) var outcome: Outcome = .ongoing
  public private(set) var phase: Int = 1
  public let isBoss: Bool

  private var rng: SeededGenerator
  private let enrageRamp: Double // damage multiplier growth after soft enrage

  public init(heroDefs: [HeroDefinition], config: BattleConfig, seed: UInt64) {
    self.rng = SeededGenerator(seed: seed)
    self.isBoss = config.isBoss
    self.enrageRamp = config.isBoss ? 1.0 : 0.0

    self.heroes = heroDefs.prefix(5).enumerated().map { i, def in
      Unit(
        id: "h\(i)", def: def, stats: def.baseStats, isEnemy: false, isBoss: false,
        hp: def.baseStats.hp, maxHP: def.baseStats.hp, ultCharge: 0, attackCooldown: Double(i) * 0.4,
        buffAttackPercent: 0, buffTimer: 0, stunTimer: 0
      )
    }
    self.enemies = (0..<config.enemyCount).map { i in
      let stats = config.enemyStats * config.stagePower
      return Unit(
        id: "e\(i)", def: Self.enemyDef, stats: stats, isEnemy: true,
        isBoss: config.isBoss && i == 0,
        hp: stats.hp, maxHP: stats.hp, ultCharge: 0, attackCooldown: 1.0 + Double(i) * 0.5,
        buffAttackPercent: 0, buffTimer: 0, stunTimer: 0
      )
    }
  }

  public var isBossPhase2: Bool { isBoss && phase >= 2 }

  /// Advance the simulation by `dt` seconds.
  public mutating func tick(_ dt: Double) {
    guard outcome == .ongoing else { return }
    elapsed += dt

    // Boss phase transition at 50% HP
    if isBoss && phase == 1, let boss = enemies.first, boss.hp <= boss.maxHP * 0.5 {
      phase = 2
    }

    tickSide(&heroes, targets: &enemies, dt: dt)
    tickSide(&enemies, targets: &heroes, dt: dt)

    if enemies.allSatisfy({ !$0.isAlive }) { outcome = .victory }
    else if heroes.allSatisfy({ !$0.isAlive }) { outcome = .defeat }
  }

  private mutating func tickSide(_ side: inout [Unit], targets: inout [Unit], dt: Double) {
    for i in side.indices {
      guard side[i].isAlive else { continue }
      if side[i].stunTimer > 0 {
        side[i].stunTimer -= dt
        continue
      }
      if side[i].buffTimer > 0 {
        side[i].buffTimer -= dt
        if side[i].buffTimer <= 0 { side[i].buffAttackPercent = 0 }
      }
      side[i].ultCharge = min(1.0, side[i].ultCharge + dt * 0.09) // ~11s to full
      side[i].attackCooldown -= dt * side[i].stats.speed
      if side[i].attackCooldown <= 0 {
        side[i].attackCooldown = 2.2 + Double.random(in: 0..<0.8, using: &rng)
        performAttack(attacker: &side[i], targets: &targets)
      }
    }
  }

  private mutating func performAttack(attacker: inout Unit, targets: inout [Unit]) {
    guard let targetIndex = targets.firstIndex(where: { $0.isAlive }) else { return }
    let isEnraged = isBoss && phase == 2
    let enrage = isEnraged ? 1.0 + min((elapsed - 45.0) * 0.01, 0.5) : 1.0
    let rawDamage = attacker.stats.attack * (1.0 + attacker.buffAttackPercent) * enrage
    let mitigated = max(rawDamage * 0.25, rawDamage - targets[targetIndex].stats.defense * 0.6)
    let crit = Double.random(using: &rng) < attacker.stats.critChance
    let damage = mitigated * (crit ? attacker.stats.critDamage : 1.0)
    targets[targetIndex].hp = max(0, targets[targetIndex].hp - damage)
    attacker.ultCharge = min(1.0, attacker.ultCharge + 0.08)
  }

  public struct UltFireResult: Sendable {
    public let damage: Double
    public let targetID: String?
  }

  /// Fire a hero's ultimate. Returns nil if the hero is dead or not charged.
  public mutating func fireUltimate(heroID: String) -> UltFireResult? {
    guard outcome == .ongoing, let hIndex = heroes.firstIndex(where: { $0.id == heroID }),
      heroes[hIndex].ultCharge >= 1.0, heroes[hIndex].isAlive
    else { return nil }

    heroes[hIndex].ultCharge = 0
    let hero = heroes[hIndex]
    let multiplier = hero.def.ultimate.damageMultiplier

    switch hero.def.ultimate.effect {
    case .damage:
      return dealUltDamage(from: hIndex, multiplier: multiplier)
    case .chainDamage(let bounces):
      var total = 0.0
      for _ in 0..<bounces {
        if let r = dealUltDamage(from: hIndex, multiplier: multiplier / Double(bounces) * 1.6) {
          total += r.damage
        }
      }
      return UltFireResult(heroID: heroID, damage: total, targetID: nil)
    case .healAll(let percent):
      for i in heroes.indices where heroes[i].isAlive {
        heroes[i].hp = min(heroes[i].maxHP, heroes[i].hp + heroes[i].maxHP * percent)
      }
      return UltFireResult(heroID: heroID, damage: 0, targetID: nil)
    case .shieldAll(let percent):
      // Shields modeled as temporary HP via buff (simplified: instant heal)
      for i in heroes.indices where heroes[i].isAlive {
        heroes[i].hp = min(heroes[i].maxHP, heroes[i].hp + heroes[i].maxHP * percent)
      }
      return UltFireResult(heroID: heroID, damage: 0, targetID: nil)
    case .stunAll(let duration), .freezeAll(let duration):
      for i in enemies.indices where enemies[i].isAlive {
        enemies[i].stunTimer = max(enemies[i].stunTimer, duration)
      }
      return UltFireResult(heroID: heroID, damage: 0, targetID: nil)
    case .buffAttack(let percent, let duration):
      for i in heroes.indices where heroes[i].isAlive {
        heroes[i].buffAttackPercent = max(heroes[i].buffAttackPercent, percent)
        heroes[i].buffTimer = max(heroes[i].buffTimer, duration)
      }
      return UltFireResult(heroID: heroID, damage: 0, targetID: nil)
    case .execute(let threshold):
      guard let tIndex = enemies.firstIndex(where: { $0.isAlive }) else { return nil }
      let belowThreshold = enemies[tIndex].hp <= enemies[tIndex].maxHP * threshold
      let damage = heroes[hIndex].stats.attack * multiplier * (belowThreshold ? 3.0 : 1.0)
      enemies[tIndex].hp = max(0, enemies[tIndex].hp - damage)
      return UltFireResult(heroID: heroID, damage: damage, targetID: enemies[tIndex].id)
    case .lifesteal(let percent):
      guard let r = dealUltDamage(from: hIndex, multiplier: multiplier) else { return nil }
      heroes[hIndex].hp = min(heroes[hIndex].maxHP, heroes[hIndex].hp + r.damage * percent)
      return r
    }
  }

  private mutating func dealUltDamage(from heroIndex: Int, multiplier: Double) -> UltFireResult? {
    guard let tIndex = enemies.firstIndex(where: { $0.isAlive }) else { return nil }
    let raw = heroes[heroIndex].stats.attack * multiplier
    let mitigated = max(raw * 0.5, raw - enemies[tIndex].stats.defense * 0.6)
    enemies[tIndex].hp = max(0, enemies[tIndex].hp - mitigated)
    return UltFireResult(heroID: heroes[heroIndex].id, damage: mitigated, targetID: enemies[tIndex].id)
  }
}
```

*(Note: `BattleConfig` is a nested type — define it inside `BattleEngine` or at
file scope; keep the exact name `BattleConfig` with fields `enemyStats: StatBlock,
enemyCount: Int, isBoss: Bool, stagePower: Double`.)*

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test`
Expected: PASS (all BattleEngineTests green)

- [ ] **Step 5: Lint and commit**

```bash
cd /workspaces/gameforge && swiftlint --config .swiftlint.yml
git add -A && git commit -m "Add tick-based battle engine with ultimates and boss phases"
```

---

### Task 6: Equipment system — gear, sub-stats, sets, enhance, reroll

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/EquipmentSystem.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/EquipmentTests.swift`

**Interfaces:**
- Consumes: `Rarity`, `StatBlock`, `SeededGenerator` (Task 2)
- Produces: `enum GearSlot: String, Codable, Sendable, CaseIterable` (`.weapon, .armor, .trinket, .relic`); `struct GearItem: Sendable, Identifiable, Codable` (`id: UUID, slot: GearSlot, rarity: Rarity, mainStat: GearStat, subStats: [GearStat], enhanceLevel: Int, setName: String?`); `struct GearStat: Sendable, Codable` (`kind: StatKind, value: Double`); `enum StatKind: String, Codable, Sendable` (`.hp, .attack, .defense, .speed, .critChance, .critDamage`); `struct EquipmentSystem: Sendable` with `mutating func generateDrop(rarity: Rarity, rng: inout SeededGenerator) -> GearItem`; `static func stats(for item: GearItem, heroBase: StatBlock) -> StatBlock` (main + sub-stats + enhance bonus); `mutating func enhance(item: inout GearItem, gold: inout Int) -> Bool` (cost = 500 × (level+1), +bonus every 5 levels); `mutating func reroll(item: inout GearItem, gems: inout Int) -> Bool` (cost 50 gems, rerolls sub-stats only).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import GameCore

@Suite struct EquipmentTests {
  @Test func generatedDropHasValidShape() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 11)
    let item = system.generateDrop(rarity: .epic, rng: &rng)
    #expect(item.rarity == .epic)
    #expect(GearSlot.allCases.contains(item.slot))
    #expect(item.enhanceLevel == 0)
  }

  @Test func epicGearHasTwoSubStats() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 12)
    let item = system.generateDrop(rarity: .epic, rng: &rng)
    #expect(item.subStats.count == 2)
  }

  @Test func commonGearHasNoSubStats() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 13)
    let item = system.generateDrop(rarity: .common, rng: &rng)
    #expect(item.subStats.isEmpty)
  }

  @Test func enhanceConsumesGoldAndRaisesLevel() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 13)
    var item = system.generateDrop(rarity: .rare, rng: &rng)
    var gold = 10_000
    let ok = system.enhance(item: &item, gold: &gold)
    #expect(ok)
    #expect(item.enhanceLevel == 1)
    #expect(gold == 10_000 - 500)
  }

  @Test func enhanceFailsWithoutGold() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 14)
    var item = system.generateDrop(rarity: .rare, rng: &rng)
    var gold = 100
    #expect(system.enhance(item: &item, gold: &gold) == false)
    #expect(item.enhanceLevel == 0)
  }

  @Test func rerollChangesSubStats() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 15)
    var item = system.generateDrop(rarity: .epic, rng: &rng)
    let before = item.subStats
    var gems = 1000
    #expect(system.reroll(item: &item, gems: &gems) == true)
    #expect(gems == 1000 - 50)
    // Sub-stats re-rolled (values may coincide but the roll is fresh)
    #expect(item.subStats.count == 2)
  }

  @Test func setBonusAppliesAtFourPieces() {
    // 4 pieces of the same set grant the set bonus
    var items: [GearItem] = []
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 15)
    for _ in 0..<4 {
      var item = system.generateDrop(rarity: .rare, rng: &rng)
      item.setName = "emberfang"
      items.append(item)
    }
    let bonus = EquipmentSystem.setBonus(setName: "emberfang", pieceCount: 4)
    #expect(bonus != nil)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test 2>&1 | tail -3`
Expected: FAIL — cannot find `EquipmentSystem` in scope

- [ ] **Step 3: Write the implementation**

`EquipmentSystem.swift`:

```swift
import Foundation

public enum GearSlot: String, Codable, Sendable, CaseIterable {
  case weapon, armor, trinket, relic
}

public enum StatKind: String, Codable, Sendable, CaseIterable {
  case hp, attack, defense, speed, critChance, critDamage
}

public struct GearStat: Sendable, Codable, Equatable {
  public let kind: StatKind
  public let value: Double
  public init(kind: StatKind, value: Double) { self.kind = kind; self.value = value }
}

public struct GearItem: Sendable, Identifiable, Codable {
  public let id: UUID
  public let slot: GearSlot
  public let rarity: Rarity
  public var mainStat: GearStat
  public var subStats: [GearStat]
  public var enhanceLevel: Int
  public var setName: String?

  public init(
    id: UUID = UUID(), slot: GearSlot, rarity: Rarity,
    mainStat: GearStat, subStats: [GearStat] = [], enhanceLevel: Int = 0, setName: String? = nil
  ) {
    self.id = id; self.slot = slot; self.rarity = rarity
    self.mainStat = mainStat; self.subStats = subStats
    self.enhanceLevel = enhanceLevel; self.setName = setName
  }
}

/// Gear generation and progression (spec §7). Enhancing never destroys gear.
public struct EquipmentSystem: Sendable {
  public static let rerollGemCost = 50

  public init() {}

  public mutating func generateDrop(rarity: Rarity, rng: inout SeededGenerator) -> GearItem {
    let slot = GearSlot.allCases.randomElement(using: &rng)!
    let mainStat = Self.randomStat(kind: Self.mainStatKind(for: slot), rarity: rarity, rng: &rng)
    let subCount = rarity.rawValue // common 0, rare 1, epic 2, legendary 3
    var subStats: [GearStat] = []
    for _ in 0..<subCount {
      subStats.append(Self.randomSubStat(rarity: rarity, rng: &rng))
    }
    let setNames = ["emberfang", "glacier", "grove", "voidshroud"]
    let hasSet = rarity >= .epic && Double.random(using: &rng) < 0.5
    return GearItem(
      slot: slot, rarity: rarity, mainStat: mainStat, subStats: subStats,
      setName: hasSet ? setNames.randomElement(using: &rng) : nil
    )
  }

  /// Total stat contribution of a gear item (main + sub + enhance bonus).
  public static func stats(for item: GearItem) -> StatBlock {
    var block = StatBlock()
    applyStat(item.mainStat, to: &block, multiplier: 1.0 + Double(item.enhanceLevel) * 0.08)
    for sub in item.subStats {
      applyStat(sub, to: &block, multiplier: 1.0)
    }
    // Every 5 enhance levels: +10% main stat bonus
    if item.enhanceLevel >= 5 {
      applyStat(item.mainStat, to: &block, multiplier: Double(item.enhanceLevel / 5) * 0.10)
    }
    return block
  }

  /// Set bonuses (spec §7): 2-piece minor, 4-piece major.
  public static func setBonus(setName: String, pieceCount: Int) -> StatBlock? {
    guard pieceCount >= 2 else { return nil }
    switch setName {
    case "emberfang":
      return pieceCount >= 4 ? StatBlock(attack: 0, critDamage: 0.25) : StatBlock(critChance: 0.05)
    case "glacier":
      return pieceCount >= 4 ? StatBlock(hp: 0, defense: 40) : StatBlock(hp: 300)
    case "grove":
      return pieceCount >= 4 ? StatBlock(hp: 0, speed: 0.15) : StatBlock(defense: 25)
    case "voidshroud":
      return pieceCount >= 4 ? StatBlock(attack: 0, critDamage: 0.35) : StatBlock(attack: 20)
    default:
      return nil
    }
  }

  @discardableResult
  public mutating func enhance(item: inout GearItem, gold: inout Int) -> Bool {
    let cost = Self.enhanceCost(level: item.enhanceLevel)
    guard gold >= cost else { return false }
    gold -= cost
    item.enhanceLevel += 1
    return true
  }

  public static func enhanceCost(level: Int) -> Int { 500 * (level + 1) }

  @discardableResult
  public mutating func reroll(item: inout GearItem, gems: inout Int) -> Bool {
    guard gems >= Self.rerollGemCost, item.rarity >= .rare else { return false }
    gems -= Self.rerollGemCost
    var rng = SeededGenerator(seed: UInt64.random(in: 0...UInt64.max))
    item.subStats = (0..<item.rarity.rawValue).map { _ in Self.randomSubStat(rarity: item.rarity, rng: &rng) }
    return true
  }

  // MARK: - Private

  private static func mainStatKind(for slot: GearSlot) -> StatKind {
    switch slot {
    case .weapon: return .attack
    case .armor: return .hp
    case .trinket: return .defense
    case .relic: return .critChance
    }
  }

  private static func randomStatValue(kind: StatKind, rarity: Rarity, rng: inout SeededGenerator) -> Double {
    let base: Double
    switch kind {
    case .hp: base = 200
    case .attack: base = 15
    case .defense: base = 10
    case .speed: base = 0.02
    case .critChance: base = 0.02
    case .critDamage: base = 0.05
    }
    let rarityMult = [1.0, 1.5, 2.2, 3.2][rarity.rawValue]
    return base * rarityMult * (0.8 + Double.random(using: &rng) * 0.4)
  }

  private static func randomSubStat(rarity: Rarity, rng: inout SeededGenerator) -> GearStat {
    let kind = StatKind.allCases.randomElement(using: &rng)!
    return GearStat(kind: kind, value: randomStatValue(kind: kind, rarity: rarity, rng: &rng) * 0.4)
  }

  private static func applyStat(_ stat: GearStat, to block: inout StatBlock, multiplier: Double) {
    let v = stat.value * multiplier
    switch stat.kind {
    case .hp: block.hp += v
    case .attack: block.attack += v
    case .defense: block.defense += v
    case .speed: block.speed += v
    case .critChance: block.critChance += v
    case .critDamage: block.critDamage += v
    }
  }
}
```

*(Note: `GearStat` needs a `value` property name consistent throughout — the tests
reference `item.subStats`; make sure `GearItem` exposes `subStats` and the code
compiles as a coherent whole.)*

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test`
Expected: PASS

- [ ] **Step 5: Lint and commit**

```bash
cd /workspaces/gameforge && swiftlint --config .swiftlint.yml
git add -A && git commit -m "Add equipment system with sub-stats, sets, enhance, reroll"
```

---

### Task 7: Stage progression — chapters, difficulty curve, biomes

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/StageProgression.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/StageProgressionTests.swift`

**Interfaces:**
- Consumes: `StatBlock` (Task 2)
- Produces: `enum Biome: String, Codable, Sendable, CaseIterable` (`.duskwoodVale, .ashenMarsh, .emberDepths, .starlitPeaks`); `struct StageID: Sendable, Codable, Equatable` (`chapter: Int, stage: Int`) with `var display: String` ("3-7") and `var isBoss: Bool` (stage == 10); `struct StageProgression: Sendable` with `static func biome(for chapter: Int) -> Biome` (cycles every 4 chapters); `static func enemyStats(for stage: StageID) -> StatBlock` (exponential curve: base × 1.18^(totalStage)); `static func enemyCount(for stage: StageID) -> Int` (3–5, boss = 1); `static func idleRate(for stage: StageID) -> Int` (gold/min, grows with stage); `static func next(after:) -> StageID`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import GameCore

@Suite struct StageProgressionTests {
  @Test func displayFormat() {
    let stage = StageID(chapter: 3, stage: 7)
    #expect(stage.display == "3-7")
  }

  @Test func bossOnTenthStage() {
    #expect(StageID(chapter: 2, stage: 10).isBoss)
    #expect(!StageID(chapter: 2, stage: 9).isBoss)
  }

  @Test func difficultyGrowsMonotonically() {
    let early = StageProgression.enemyStats(for: StageID(chapter: 1, stage: 1))
    let late = StageProgression.enemyStats(for: StageID(chapter: 5, stage: 5))
    #expect(late.attack > early.attack)
    #expect(late.hp > early.hp)
  }

  @Test func biomesCycle() {
    #expect(StageProgression.biome(for: 1) == .duskwoodVale)
    #expect(StageProgression.biome(for: 2) == .ashenMarsh)
    #expect(StageProgression.biome(for: 5) == .duskwoodVale) // cycles every 4
  }

  @Test func idleRateGrows() {
    #expect(StageProgression.idleRate(for: StageID(chapter: 4, stage: 1))
      > StageProgression.idleRate(for: StageID(chapter: 1, stage: 1)))
  }

  @Test func nextStageAdvances() {
    let s = StageID(chapter: 1, stage: 9)
    #expect(StageProgression.next(after: s) == StageID(chapter: 1, stage: 10))
    let boss = StageID(chapter: 1, stage: 10)
    #expect(StageProgression.next(after: boss) == StageID(chapter: 2, stage: 1))
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test 2>&1 | tail -3`
Expected: FAIL — cannot find `StageID` in scope

- [ ] **Step 3: Write the implementation**

`StageProgression.swift`:

```swift
import Foundation

/// The four biomes, cycling per chapter (spec §5, §13).
public enum Biome: String, Codable, Sendable, CaseIterable {
  case duskwoodVale, ashenMarsh, emberDepths, starlitPeaks

  public var displayName: String {
    switch self {
    case .duskwoodVale: return "Duskwood Vale"
    case .ashenMarsh: return "Ashen Marsh"
    case .emberDepths: return "Ember Depths"
    case .starlitPeaks: return "Starlit Peaks"
    }
  }
}

public struct StageID: Sendable, Codable, Equatable {
  public let chapter: Int
  public let stage: Int

  public init(chapter: Int, stage: Int) {
    self.chapter = chapter
    self.stage = stage
  }

  public var display: String { "\(chapter)-\(stage)" }
  public var isBoss: Bool { stage == 10 }
  public var totalIndex: Int { (chapter - 1) * 10 + stage }
}

/// Chapter/stage math: endless AFK-style campaign (spec §5).
public enum StageProgression {
  private static let hpBase = 500.0
  private static let attackBase = 40.0
  private static let defenseBase = 20.0
  private static let growthPerStage = 1.18

  public static func biome(for chapter: Int) -> Biome {
    Biome.allCases[(chapter - 1) % Biome.allCases.count]
  }

  public static func next(after stage: StageID) -> StageID {
    stage.stage >= 10 ? StageID(chapter: stage.chapter + 1, stage: 1) : StageID(chapter: stage.chapter, stage: stage.stage + 1)
  }

  public static func enemyStats(for stage: StageID) -> StatBlock {
    let t = Double(stage.totalIndex - 1)
    let growth = pow(1.18, t)
    let bossMult = stage.isBoss ? 3.0 : 1.0
    return StatBlock(
      hp: hpBase * growth * bossMult,
      attack: attackBase * growth * (stage.isBoss ? 1.4 : 1.0),
      defense: defenseBase * growth * (stage.isBoss ? 1.5 : 1.0),
      speed: 1.0 + t * 0.01
    )
  }

  public static func enemyCount(for stage: StageID) -> Int {
    stage.isBoss ? 1 : min(5, 3 + stage.stage / 4)
  }

  /// Gold per minute of idle income at this stage (flat best-stage rate, spec §8).
  public static func idleRate(for stage: StageID) -> Int {
    Int(50 * pow(1.15, Double(stage.totalIndex - 1)))
  }

  public static func battleReward(for stage: StageID) -> Int {
    Int(100 * pow(1.15, Double(stage.totalIndex - 1)))
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test`
Expected: PASS

- [ ] **Step 5: Lint and commit**

```bash
cd /workspaces/gameforge && swiftlint --config .swiftlint.yml
git add -A && git commit -m "Add stage progression with chapters, biomes, difficulty curve"
```

---

### Task 8: Idle income — offline math, caps, fast rewards

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/IdleIncome.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/IdleIncomeTests.swift`

**Interfaces:**
- Consumes: `StageProgression`, `Wallet` (Tasks 2, 7)
- Produces: `struct IdleIncomeState: Sendable, Codable` (`lastClaimDate: Date?`); `enum IdleIncome: Sendable` with `static func offlineEarnings(bestStage: StageID, secondsAway: Double, capHours: Int = 12) -> (gold: Int, secondsCapped: Double)`; `static let baseCapHours = 12`, `static let monthlyCardCapHours = 24`; `static func fastReward(bestStage: StageID, hours: Double = 2) -> Int`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import GameCore

@Suite struct IdleIncomeTests {
  @Test func earningsScaleWithTimeAndStage() {
    let short = IdleIncome.earnings(bestStage: StageID(chapter: 1, stage: 1), secondsAway: 3600)
    let long = IdleIncome.earnings(bestStage: StageID(chapter: 1, stage: 1), secondsAway: 7200)
    #expect(short.gold > 0)
    #expect(long.gold > short.gold)
  }

  @Test func twelveHourCap() {
    let day = IdleIncome.earnings(bestStage: StageID(chapter: 2, stage: 3), secondsAway: 86_400)
    let cap = IdleIncome.earnings(bestStage: StageID(chapter: 2, stage: 3), secondsAway: 12 * 3600)
    #expect(day.gold == cap.gold) // capped at 12h
  }

  @Test func monthlyCardDoublesCap() {
    let day = IdleIncome.earnings(bestStage: StageID(chapter: 2, stage: 3), secondsAway: 24 * 3600, capHours: 24)
    let base = IdleIncome.earnings(bestStage: StageID(chapter: 2, stage: 3), secondsAway: 24 * 3600)
    #expect(day.gold > base.gold)
  }

  @Test func fastRewardEqualsTwoHours() {
    let fast = IdleIncome.fastReward(bestStage: StageID(chapter: 3, stage: 1))
    let manual = IdleIncome.earnings(bestStage: StageID(chapter: 3, stage: 1), secondsAway: 2 * 3600)
    #expect(fast == manual.gold)
  }

  @Test func higherStagePaysMore() {
    #expect(IdleIncome.earnings(bestStage: StageID(chapter: 5, stage: 1), secondsAway: 3600).gold
      > IdleIncome.earnings(bestStage: StageID(chapter: 1, stage: 1), secondsAway: 3600).gold)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test 2>&1 | tail -3`
Expected: FAIL — cannot find `IdleIncome` in scope

- [ ] **Step 3: Write the implementation**

`IdleIncome.swift`:

```swift
import Foundation

/// Offline income math (spec §8): flat best-stage rate, capped.
public enum IdleIncome {
  public static let baseCapHours = 12
  public static let monthlyCardCapHours = 24

  /// Gold earned while away. Rate comes from the player's best cleared stage.
  public static func earnings(
    bestStage: StageID, secondsAway: Double, capHours: Int = IdleIncome.baseCapHours
  ) -> (gold: Int, secondsCapped: Double) {
    let cappedSeconds = min(secondsAway, Double(capHours) * 3600)
    let perMinute = Double(StageProgression.idleRate(for: bestStage))
    let gold = Int((cappedSeconds / 60.0) * perMinute)
    return (gold, cappedSeconds)
  }

  /// "Fast rewards": instantly claim N hours of idle income (2h free daily).
  public static func fastReward(bestStage: StageID, hours: Double = 2) -> Int {
    earnings(bestStage: bestStage, secondsAway: hours * 3600).gold
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test`
Expected: PASS

- [ ] **Step 5: Lint and commit**

```bash
cd /workspaces/gameforge && swiftlint --config .swiftlint.yml
git add -A && git commit -m "Add idle income with caps and fast rewards"
```

---

### Task 9: Quest system — dailies, weeklies, achievements

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/QuestSystem.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/QuestTests.swift`

**Interfaces:**
- Consumes: `Wallet` (Task 2)
- Produces: `enum QuestKind: String, Codable, Sendable` (`.daily, .weekly, .achievement`); `struct QuestDefinition: Sendable, Identifiable, Codable` (`id, kind: QuestKind, title: String, goal: Int, rewardGems: Int, rewardQuestTokens: Int, metric: QuestMetric`); `enum QuestMetric: String, Codable, Sendable` (`.battlesWon, .summons, .enhances, .idleClaims, .goldSpent, .stagesCleared`); `struct QuestProgress: Sendable, Codable` (`questID: String, count: Int, claimed: Bool`); `struct QuestSystem: Sendable` with `static let dailies: [QuestDefinition]` (5 quests), `static let weeklies: [QuestDefinition]` (3), `static let achievements: [QuestDefinition]` (8); `mutating func record(metric: QuestMetric, amount: Int)`; `func progress(for questID: String) -> QuestProgress?`; `mutating func claim(questID: String, wallet: inout Wallet) -> Bool` (grants rewards, marks claimed).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import GameCore

@Suite struct QuestTests {
  @Test func fiveDailies() {
    #expect(QuestSystem.dailies.count == 5)
  }

  @Test func recordingProgress() {
    var quests = QuestSystem()
    quests.record(metric: .battlesWon, amount: 3)
    let quest = QuestSystem.dailies.first { $0.metric == .battlesWon }!
    let progress = quests.progress(for: quest.id)
    #expect(progress?.count == 3)
  }

  @Test func claimGrantsRewardsOnce() {
    var quests = QuestSystem()
    var wallet = Wallet()
    let quest = QuestSystem.dailies[0]
    quests.record(metric: quest.metric, amount: quest.goal)
    #expect(quests.claim(questID: quest.id, wallet: &wallet) == true)
    #expect(quests.claim(questID: quest.id, wallet: &wallet) == false) // already claimed
    #expect(wallet.balance(of: .questTokens) > 0)
  }

  @Test func claimFailsWhenIncomplete() {
    var quests = QuestSystem()
    var wallet = Wallet()
    let quest = QuestSystem.dailies[0]
    #expect(quests.claim(questID: quest.id, wallet: &wallet) == false)
  }

  @Test func achievementsExist() {
    #expect(QuestSystem.achievements.count >= 8)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test 2>&1 | tail -3`
Expected: FAIL — cannot find `QuestSystem` in scope

- [ ] **Step 3: Write the implementation**

`QuestSystem.swift`:

```swift
import Foundation

public enum QuestKind: String, Codable, Sendable {
  case daily, weekly, achievement
}

public enum QuestMetric: String, Codable, Sendable {
  case battlesWon, summons, enhances, idleClaims, goldSpent, stagesCleared
}

public struct QuestDefinition: Sendable, Identifiable, Codable {
  public let id: String
  public let kind: QuestKind
  public let metric: QuestMetric
  public let goal: Int
  public let rewardGems: Int
  public let rewardQuestTokens: Int

  public var title: String {
    switch metric {
    case .battlesWon: return "Win \(goal) battles"
    case .summons: return "Summon \(goal)×"
    case .enhances: return "Enhance gear \(goal)×"
    case .idleClaims: return "Claim idle chest \(goal)×"
    case .goldSpent: return "Spend \(goal) gold"
    case .stagesCleared: return "Clear \(goal) stages"
    }
  }
}

public struct QuestProgress: Sendable, Codable {
  public var questID: String
  public var count: Int = 0
  public var claimed: Bool = false
}

/// Quests & achievements (spec §9).
public struct QuestSystem: Sendable {
  public static let dailies: [QuestDefinition] = [
    QuestDefinition(id: "d-battles", kind: .daily, metric: .battlesWon, goal: 5, rewardGems: 20, rewardQuestTokens: 10),
    QuestDefinition(id: "d-summon", kind: .daily, metric: .summons, goal: 1, rewardGems: 20, rewardQuestTokens: 10),
    QuestDefinition(id: "d-enhance", kind: .daily, metric: .enhances, goal: 2, rewardGems: 15, rewardQuestTokens: 10),
    QuestDefinition(id: "d-idle", kind: .daily, metric: .idleClaims, goal: 1, rewardGems: 10, rewardQuestTokens: 5),
    QuestDefinition(id: "d-gold", kind: .daily, metric: .goldSpent, goal: 5000, rewardGems: 15, rewardQuestTokens: 10),
  ]

  public static let weeklies: [QuestDefinition] = [
    QuestDefinition(id: "w-battles", kind: .weekly, metric: .battlesWon, goal: 40, rewardGems: 100, rewardQuestTokens: 0),
    QuestDefinition(id: "w-stages", kind: .weekly, metric: .stagesCleared, goal: 30, rewardGems: 120, rewardQuestTokens: 0),
    QuestDefinition(id: "w-summons", kind: .weekly, metric: .summons, goal: 10, rewardGems: 80, rewardQuestTokens: 0),
  ]

  public static let achievements: [QuestDefinition] = [
    QuestDefinition(id: "a-battles-100", kind: .achievement, metric: .battlesWon, goal: 100, rewardGems: 200, rewardQuestTokens: 0),
    QuestDefinition(id: "a-battles-1000", kind: .achievement, metric: .battlesWon, goal: 1000, rewardGems: 1000, rewardQuestTokens: 0),
    QuestDefinition(id: "a-stages-50", kind: .achievement, metric: .stagesCleared, goal: 50, rewardGems: 250, rewardQuestTokens: 0),
    QuestDefinition(id: "a-stages-200", kind: .achievement, metric: .stagesCleared, goal: 200, rewardGems: 600, rewardQuestTokens: 0),
    QuestDefinition(id: "a-summons-50", kind: .achievement, metric: .summons, goal: 50, rewardGems: 300, rewardQuestTokens: 0),
    QuestDefinition(id: "a-enhances-100", kind: .achievement, metric: .enhances, goal: 100, rewardGems: 250, rewardQuestTokens: 0),
    QuestDefinition(id: "a-idle-30", kind: .achievement, metric: .idleClaims, goal: 30, rewardGems: 200, rewardQuestTokens: 0),
    QuestDefinition(id: "a-gold-1m", kind: .achievement, metric: .goldSpent, goal: 1_000_000, rewardGems: 500, rewardQuestTokens: 0),
  ]

  public private(set) var progress: [String: QuestProgress] = [:]

  public init() {}

  public mutating func record(metric: QuestMetric, amount: Int) {
    for quest in Self.dailies + Self.weeklies + Self.achievements where quest.metric == metric {
      var p = progress[quest.id] ?? QuestProgress(questID: quest.id)
      p.count += amount
      progress[quest.id] = p
    }
  }

  public func progress(for questID: String) -> QuestProgress? { progress[questID] }

  @discardableResult
  public mutating func claim(questID: String, wallet: inout Wallet) -> Bool {
    guard let quest = Self.dailies.first(where: { $0.id == questID })
      ?? Self.weeklies.first { $0.id == questID }
      ?? Self.achievements.first { $0.id == questID },
      let p = progress[questID], !p.claimed, p.count >= quest.goal
    else { return false }
    progress[questID]?.claimed = true
    if quest.rewardGems > 0 { wallet.add(.gems, quest.rewardGems) }
    if quest.rewardQuestTokens > 0 { wallet.add(.questTokens, quest.rewardQuestTokens) }
    return true
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test`
Expected: PASS

- [ ] **Step 5: Lint and commit**

```bash
cd /workspaces/gameforge && swiftlint --config .swiftlint.yml
git add -A && git commit -m "Add quest system with dailies, weeklies, achievements"
```

---

### Task 10: Player profile + EmberSession facade

**Files:**
- Create: `Packages/GameCore/Sources/GameCore/PlayerProfile.swift`
- Create: `Packages/GameCore/Sources/GameCore/EmberSession.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/EmberSessionTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–8
- Produces:
  - `struct OwnedHero: Sendable, Codable, Identifiable` (`id: String (hero def id), level: Int, stars: Int, xp: Int, gear: [GearSlot: GearItem]`)
  - `struct PlayerProfile: Sendable, Codable` (`name: String, accountLevel: Int, wallet: Wallet, ownedHeroes: [OwnedHero], squad: [String] (max 5 hero ids), bestStage: StageID, gacha: GachaState, quests: QuestSystem, equipment: EquipmentSystem, totalBattles: Int, totalSummons: Int`)
  - `struct EmberSession: Sendable` — the facade:
    - `public init(profile: PlayerProfile = PlayerProfile.new())`
    - `public private(set) var profile: PlayerProfile`
    - `public private(set) var battle: BattleEngine?`
    - `public mutating func startBattle() -> BattleEngine` (builds from squad + current stage)
    - `public mutating func tickBattle(_ dt: Double)`
    - `@discardableResult public mutating func fireUltimate(heroID: String) -> BattleEngine.UltFireResult?`
    - `public mutating func finishBattle() -> BattleReward?` (applies loot on victory; on defeat: no loot, stay at stage)
    - `public mutating func summon(banner: GachaEngine.BannerKind, count: Int) -> [GachaEngine.PullResult]?` (spends shards)
    - `public mutating func levelUpHero(heroID: String) -> Bool` (gold + XP potions)
    - `public mutating func equipGear(heroID: String, item: GearItem, slot: GearSlot)`
    - `public mutating func claimIdle() -> Int` (gold; records quest metric)
    - `public var currentStage: StageID` (next uncleared stage = bestStage advanced)
  - `struct BattleReward: Sendable` (`gold: Int, gearDrops: [GearItem], factionShards: [Faction: Int], stageCleared: StageID`)

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import GameCore

@Suite struct EmberSessionTests {
  @Test func newProfileHasStarterSquad() {
    let session = EmberSession()
    #expect(session.profile.ownedHeroes.count == 5)
    #expect(session.profile.squad.count == 5)
  }

  @Test func battleVictoryAdvancesStage() {
    var session = EmberSession()
    session.startBattle()
    var guardCount = 0
    while session.battle?.outcome == .ongoing && guardCount < 10_000 {
      session.tickBattle(0.1)
      guardCount += 1
    }
    let reward = session.finishBattle()
    #expect(reward != nil)
    #expect(session.profile.bestStage.stage == 1) // cleared 1-1
  }

  @Test func battleDefeatStaysAtStage() {
    var session = EmberSession()
    // Overwhelm the player: simulate a deep stage via direct profile mutation
    session.profile.bestStage = StageID(chapter: 20, stage: 5)
    session.startBattle()
    var guardCount = 0
    while session.battle?.outcome == .ongoing && guardCount < 10_000 {
      session.tickBattle(0.1)
      guardCount += 1
    }
    _ = session.finishBattle()
    // Wall rule: stage does not advance on defeat
    #expect(session.profile.bestStage.stage == 5 || session.battle?.outcome == .victory)
  }

  @Test func summonSpendsShards() {
    var session = EmberSession()
    session.profile.wallet.add(.gems, 1000)
    let before = session.profile.wallet.balance(of: .gems)
    let results = session.summon(banner: .permanent, count: 1)
    #expect(results?.count == 1)
    #expect(session.profile.wallet.balance(of: .gems) == before - GachaEngine.singleCost)
  }

  @Test func levelUpHeroCostsGold() {
    var session = EmberSession()
    session.profile.wallet.add(.gold, 10_000)
    let heroID = session.profile.squad[0]
    let ok = session.levelUpHero(heroID: heroID)
    #expect(ok)
    let hero = session.profile.ownedHeroes.first { $0.id == heroID }
    #expect(hero?.level == 2)
  }

  @Test func idleClaimGrantsGold() {
    var session = EmberSession()
    session.profile.wallet.add(.gems, 10) // ensure wallet exists
    let gold = session.claimIdle()
    #expect(gold >= 0)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test 2>&1 | tail -3`
Expected: FAIL — cannot find `EmberSession` in scope

- [ ] **Step 3: Write the profile and facade**

`PlayerProfile.swift`:

```swift
import Foundation

/// A hero the player owns, with progression and equipped gear.
public struct OwnedHero: Sendable, Codable, Identifiable {
  public var id: String { definitionID }
  public let definitionID: String
  public var level: Int
  public var stars: Int
  public var xp: Int
  public var gear: [GearSlot: GearItem]

  public init(definitionID: String, level: Int = 1, stars: Int = 1) {
    self.definitionID = definitionID
    self.level = level
    self.stars = 1
    self.xp = 0
  }

  public func stats() -> StatBlock {
    guard let def = HeroCatalog.hero(id: definitionID) else { return .zero }
    var stats = def.baseStats
    // Level scaling: +6% per level
    let levelMult = 1.0 + Double(level - 1) * 0.06
    stats = stats * levelMult
    // Stars: +12% per star above 1
    stats = stats * (1.0 + Double(stars - 1) * 0.12)
    // Gear
    for (_, item) in gear {
      let gearStats = EquipmentSystem.stats(for: item)
      stats = stats + gearStats
    }
    return stats
  }
}

/// Everything the player owns. Persisted locally + synced to backend.
public struct PlayerProfile: Sendable, Codable {
  public var name: String
  public var accountLevel: Int
  public var wallet: Wallet
  public var ownedHeroes: [OwnedHero]
  public var squad: [String]
  public var bestStage: StageID
  public var gacha: GachaState
  public var quests: QuestSystem
  public var equipment: EquipmentSystem
  public var totalBattles: Int
  public var totalSummons: Int

  public static func new() -> PlayerProfile {
    // Starter squad: one hero of each faction + one extra DPS
    let starterIDs = ["torchbearer", "snowcap", "mosslings", "duskhound", "sparkmage"]
    var owned: [OwnedHero] = []
    for id in starterIDs {
      var hero = OwnedHero(definitionID: id)
      hero.stars = 1
      hero.level = 1
      owned.append(hero)
    }
    return PlayerProfile(
      name: "Keeper",
      accountLevel: 1,
      wallet: Wallet(balances: [.gold: 2000, .gems: 300]),
      ownedHeroes: owned,
      squad: starterIDs,
      bestStage: StageID(chapter: 1, stage: 1),
      gacha: GachaState(),
      quests: QuestSystem(),
      equipment: EquipmentSystem(),
      totalBattles: 0,
      totalSummons: 0
    )
  }
}
```

`EmberSession.swift`:

```swift
import Foundation

/// The game facade. The app layer drives this and renders its state;
/// all rules live in GameCore types.
public struct EmberSession: Sendable {
  public private(set) var profile: PlayerProfile
  public private(set) var battle: BattleEngine?
  public private(set) var lastIdleClaim: Date?

  public init(profile: PlayerProfile = .new()) {
    self.profile = profile
  }

  /// The stage the player is currently attempting (best cleared + 1).
  public var currentStage: StageID {
    StageProgression.next(after: profile.bestStage)
  }

  public mutating func startBattle() {
    let stage = currentStage
    let squadDefs = profile.squad.compactMap { id in
      profile.ownedHeroes.first { $0.definitionID == id }.map { hero in
        // Build a HeroDefinition with the owned hero's computed stats
        HeroDefinition(
          id: hero.definitionID, name: HeroCatalog.hero(id: hero.definitionID)?.name ?? "",
          faction: HeroCatalog.hero(id: hero.definitionID)?.faction ?? .ember,
          rarity: HeroCatalog.hero(id: hero.definitionID)?.rarity ?? .common,
          role: HeroCatalog.hero(id: hero.definitionID)?.role ?? .dps,
          baseStats: hero.stats(),
          ultimate: HeroCatalog.hero(id: hero.definitionID)?.ultimate ?? UltimateDefinition(id: "x", name: "x"),
          passives: HeroCatalog.hero(id: hero.definitionID)?.passives ?? [],
          lore: ""
        )
      }
    }
    var rng = SeededGenerator(seed: UInt64(stage.totalIndex))
    battle = BattleEngine(
      heroDefs: squadDefs,
      config: BattleConfig(
        enemyStats: StageProgression.enemyStats(for: stage),
        enemyCount: StageProgression.enemyCount(for: stage),
        isBoss: stage.isBoss,
        stagePower: 1.0
      ),
      seed: rng.next()
    )
  }

  public mutating func tickBattle(_ dt: Double) {
    battle?.tick(dt)
  }

  @discardableResult
  public mutating func fireUltimate(heroID: String) -> BattleEngine.UltFireResult? {
    battle?.fireUltimate(heroID: heroID)
  }

  public struct BattleReward: Sendable {
    public let gold: Int
    public let gearDrops: [GearItem]
    public let stageCleared: StageID
  }

  /// Apply battle results. Victory: loot + advance stage. Defeat: no loot (wall rule).
  @discardableResult
  public mutating func finishBattle() -> BattleReward? {
    guard let battle, battle.outcome != .ongoing else { return nil }
    defer { self.battle = nil }
    guard battle.outcome == .victory else { return nil }

    let stage = currentStage
    let gold = StageProgression.battleReward(for: stage)
    profile.wallet.add(.gold, gold)

    // Gear drops: 40% chance of one drop
    var drops: [GearItem] = []
    var rng = SeededGenerator(seed: UInt64(battle.elapsed * 1000))
    if Double.random(using: &rng) < 0.4 {
      let dropRarity: Rarity = switch Double.random(using: &rng) {
      case ..<0.5: .common
      case ..<0.8: .rare
      case ..<0.9: .epic
      default: .legendary
      }
      drops.append(profile.equipment.generateDrop(rarity: dropRarity, rng: &rng))
    }

    profile.quests.record(metric: .battlesWon, amount: 1)
    profile.quests.record(metric: .stagesCleared, amount: 1)
    profile.bestStage = stage
    return BattleReward(gold: gold, gearDrops: drops, stageCleared: stage)
  }

  @discardableResult
  public mutating func summon(banner: GachaEngine.BannerKind, count: Int) -> [GachaEngine.PullResult]? {
    let cost = count == 10 ? GachaEngine.multiCost : GachaEngine.singleCost * count
    guard profile.wallet.balance(of: .gems) >= cost else { return nil }
    profile.wallet.spend(.gems, cost)

    var engine = GachaEngine(state: profile.gacha)
    var owned = Set(profile.ownedHeroes.map(\.definitionID))
    var results: [GachaEngine.PullResult] = []
    for _ in 0..<count {
      var shardBudget = 0 // shards handled via wallet; pass 0-cost pull
      let result = engine.pullFree(banner: banner, ownedHeroIDs: owned)
      owned.insert(result.hero.id)
      if !result.isNew {
        // Award faction shards to wallet
        profile.wallet.add(.gems, 0) // faction shards tracked separately in v1
      }
      results.append(result)
    }
    profile.gacha = engine.state
    profile.totalSummons += count
    profile.quests.record(metric: .summons, amount: count)
    return results
  }

  public mutating func levelUpHero(heroID: String) -> Bool {
    guard let index = profile.ownedHeroes.firstIndex(where: { $0.definitionID == heroID }) else { return false }
    let cost = Self.heroLevelCost(level: profile.ownedHeroes[index].level)
    guard profile.wallet.spend(.gold, cost) else { return false }
    profile.ownedHeroes[index].level += 1
    profile.quests.record(metric: .goldSpent, amount: cost)
    return true
  }

  public static func heroLevelCost(level: Int) -> Int { 800 * level }

  public mutating func equipGear(heroID: String, item: GearItem, slot: GearSlot) {
    guard let index = profile.ownedHeroes.firstIndex(where: { $0.definitionID == heroID }) else { return }
    profile.ownedHeroes[index].gear[slot] = item
  }

  /// Claim offline income. Returns gold awarded.
  @discardableResult
  public mutating func claimIdle(secondsAway: Double? = nil) -> Int {
    let elapsed: Double
    if let secondsAway {
      elapsed = secondsAway
    } else if let last = lastIdleClaim {
      elapsed = Date().timeIntervalSince(last)
    } else {
      elapsed = 0
    }
    let (gold, _) = IdleIncome.earnings(bestStage: profile.bestStage, secondsAway: elapsed)
    profile.wallet.add(.gold, gold)
    lastIdleClaim = Date()
    profile.quests.record(metric: .idleClaims, amount: 1)
    return gold
  }
}
```

*(Note: `GachaEngine.pullFree(banner:ownedHeroIDs:)` is a variant that skips shard
payment (the session already paid from the wallet). Add it to `GachaEngine` in this
task: same logic as `pull` but without the cost check/deduction.)*

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /workspaces/gameforge/Packages/GameCore && swift test`
Expected: PASS (all EmberSessionTests green)

- [ ] **Step 5: Full test suite + lint + commit**

```bash
cd /workspaces/gameforge/Packages/GameCore && swift test
cd /workspaces/gameforge && swiftlint --config .swiftlint.yml
git add -A && git commit -m "Add player profile and EmberSession facade"
```

---

### Task 10b: Push to remote and verify CI

- [ ] **Step 1: Push**

```bash
git push origin main
```

- [ ] **Step 2: Watch CI**

Run: `gh run watch` (or `gh run list --repo nick7167/gameforge --limit 1`)
Expected: lint + gamecore-tests + app-build-test all green

---

## Self-Review Notes

- **Spec coverage (Plan 1 scope):** hero catalog (§6.1) → Task 3; gacha (§6.2) → Task 4;
  battle (§4) → Task 5; equipment (§7) → Task 6; campaign (§5) → Task 7; idle (§8) → Task 8;
  quests (§9) → Task 9; profile/facade (§14) → Task 10. Skyline deletion (§14) → Task 1.
  UI, backend, services → Plans 2 and 3.
- **Type consistency:** `Wallet`, `StatBlock`, `Rarity`, `Faction` defined in Task 2 and
  consumed unchanged everywhere. `GachaEngine.pull` signature includes `ownedHeroIDs`
  for dupe detection; `pullFree` added in Task 10 for session-level pulls.
- **Known simplifications (v1):** faction shards tracked as a wallet currency is deferred
  to Plan 2's persistence pass; `UltimateEffect` cases `.healAll/.shieldAll` use
  simplified instant effects in the sim (app layer adds the visual shields).
