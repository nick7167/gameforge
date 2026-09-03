import Foundation

/// Configuration for a battle: enemy composition and stage scaling (spec §4).
public struct BattleConfig: Sendable {
  public let enemyStats: StatBlock
  public let enemyCount: Int
  public let isBoss: Bool
  public let stagePower: Double

  public init(enemyStats: StatBlock, enemyCount: Int, isBoss: Bool, stagePower: Double) {
    self.enemyStats = enemyStats
    self.enemyCount = enemyCount
    self.isBoss = isBoss
    self.stagePower = stagePower
  }
}

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

  public struct UltFireResult: Sendable {
    public let heroID: String
    public let damage: Double
    public let crit: Bool
    public let targetID: String?

    public init(heroID: String, damage: Double, crit: Bool, targetID: String?) {
      self.heroID = heroID
      self.damage = damage
      self.crit = crit
      self.targetID = targetID
    }
  }

  public private(set) var heroes: [Unit]
  public private(set) var enemies: [Unit]
  public private(set) var elapsed: Double = 0
  public private(set) var outcome: Outcome = .ongoing
  public private(set) var phase: Int = 1
  public let isBoss: Bool

  private var rng: SeededGenerator

  /// Placeholder enemy definition — enemies are stat-block driven, not catalog driven.
  private static let enemyDef = HeroDefinition(
    id: "enemy", name: "Enemy", faction: .void, rarity: .common, role: .dps,
    baseStats: StatBlock(hp: 100, attack: 10, defense: 5, speed: 1.0),
    ultimate: UltimateDefinition(id: "enemy-strike", name: "Strike", damageMultiplier: 1.5, effect: .damage),
    passives: [
      PassiveDefinition(id: "enemy-p1", name: "Thick Hide", description: "Takes slightly less damage."),
      PassiveDefinition(id: "enemy-p2", name: "Bloodlust", description: "Attacks faster when wounded.")
    ],
    lore: "A creature of the Emberfall's wilds."
  )

  public init(heroDefs: [HeroDefinition], config: BattleConfig, seed: UInt64) {
    self.rng = SeededGenerator(seed: seed)
    self.isBoss = config.isBoss

    self.heroes = heroDefs.prefix(5).enumerated().map { index, def in
      Unit(
        id: "h\(index)", def: def, stats: def.baseStats, isEnemy: false, isBoss: false,
        hp: def.baseStats.hp, maxHP: def.baseStats.hp, ultCharge: 0, attackCooldown: Double(index) * 0.4,
        buffAttackPercent: 0, buffTimer: 0, stunTimer: 0
      )
    }
    self.enemies = (0..<config.enemyCount).map { index in
      let stats = config.enemyStats * config.stagePower
      return Unit(
        id: "e\(index)", def: Self.enemyDef, stats: stats, isEnemy: true,
        isBoss: config.isBoss && index == 0,
        hp: stats.hp, maxHP: stats.hp, ultCharge: 0, attackCooldown: 1.0 + Double(index) * 0.5,
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

    var heroCopy = heroes
    var enemyCopy = enemies
    tickSide(&heroCopy, targets: &enemyCopy, dt: dt)
    tickSide(&enemyCopy, targets: &heroCopy, dt: dt)
    heroes = heroCopy
    enemies = enemyCopy

    if enemies.allSatisfy({ !$0.isAlive }) {
      outcome = .victory
    } else if heroes.allSatisfy({ !$0.isAlive }) {
      outcome = .defeat
    }
  }

  private mutating func tickSide(_ side: inout [Unit], targets: inout [Unit], dt: Double) {
    for idx in side.indices {
      guard side[idx].isAlive else { continue }
      if side[idx].stunTimer > 0 {
        side[idx].stunTimer -= dt
        continue
      }
      if side[idx].buffTimer > 0 {
        side[idx].buffTimer -= dt
        if side[idx].buffTimer <= 0 { side[idx].buffAttackPercent = 0 }
      }
      side[idx].ultCharge = min(1.0, side[idx].ultCharge + dt * 0.09) // ~11s to full
      side[idx].attackCooldown -= dt * side[idx].stats.speed
      if side[idx].attackCooldown <= 0 {
        side[idx].attackCooldown = 2.2 + Double.random(in: 0..<0.8, using: &rng)
        performAttack(attacker: &side[idx], targets: &targets)
      }
    }
  }

  private mutating func performAttack(attacker: inout Unit, targets: inout [Unit]) {
    guard let targetIndex = targets.firstIndex(where: { $0.isAlive }) else { return }
    let isEnraged = isBoss && phase == 2
    let enrage = isEnraged ? 1.0 + min((elapsed - 45.0) * 0.01, 0.5) : 1.0
    let rawDamage = attacker.stats.attack * (1.0 + attacker.buffAttackPercent) * enrage
    let mitigated = max(rawDamage * 0.25, rawDamage - targets[targetIndex].stats.defense * 0.6)
    let crit = Double.random(in: 0..<1.0, using: &rng) < attacker.stats.critChance
    let damage = mitigated * (crit ? attacker.stats.critDamage : 1.0)
    targets[targetIndex].hp = max(0, targets[targetIndex].hp - damage)
    attacker.ultCharge = min(1.0, attacker.ultCharge + 0.08)
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
      return applyChainDamage(heroID: heroID, from: hIndex, multiplier: multiplier, bounces: bounces)
    case .healAll(let percent):
      return applyHealAll(heroID: heroID, percent: percent)
    case .shieldAll(let percent):
      // Shields modeled as temporary HP via buff (simplified: instant heal)
      return applyHealAll(heroID: heroID, percent: percent)
    case .stunAll(let duration), .freezeAll(let duration):
      return applyStunAll(heroID: heroID, duration: duration)
    case .buffAttack(let percent, let duration):
      return applyBuffAttack(heroID: heroID, percent: percent, duration: duration)
    case .execute(let threshold):
      return applyExecute(heroID: heroID, from: hIndex, multiplier: multiplier, threshold: threshold)
    case .lifesteal(let percent):
      guard let result = dealUltDamage(from: hIndex, multiplier: multiplier) else { return nil }
      heroes[hIndex].hp = min(heroes[hIndex].maxHP, heroes[hIndex].hp + result.damage * percent)
      return result
    }
  }

  private mutating func applyChainDamage(heroID: String, from heroIndex: Int, multiplier: Double, bounces: Int) -> UltFireResult {
    var total = 0.0
    for _ in 0..<bounces {
      if let bounce = dealUltDamage(from: heroIndex, multiplier: multiplier / Double(bounces) * 1.6) {
        total += bounce.damage
      }
    }
    return UltFireResult(heroID: heroID, damage: total, crit: false, targetID: nil)
  }

  private mutating func applyHealAll(heroID: String, percent: Double) -> UltFireResult {
    for idx in heroes.indices where heroes[idx].isAlive {
      heroes[idx].hp = min(heroes[idx].maxHP, heroes[idx].hp + heroes[idx].maxHP * percent)
    }
    return UltFireResult(heroID: heroID, damage: 0, crit: false, targetID: nil)
  }

  private mutating func applyStunAll(heroID: String, duration: Double) -> UltFireResult {
    for idx in enemies.indices where enemies[idx].isAlive {
      enemies[idx].stunTimer = max(enemies[idx].stunTimer, duration)
    }
    return UltFireResult(heroID: heroID, damage: 0, crit: false, targetID: nil)
  }

  private mutating func applyBuffAttack(heroID: String, percent: Double, duration: Double) -> UltFireResult {
    for idx in heroes.indices where heroes[idx].isAlive {
      heroes[idx].buffAttackPercent = max(heroes[idx].buffAttackPercent, percent)
      heroes[idx].buffTimer = max(heroes[idx].buffTimer, duration)
    }
    return UltFireResult(heroID: heroID, damage: 0, crit: false, targetID: nil)
  }

  private mutating func applyExecute(heroID: String, from heroIndex: Int, multiplier: Double, threshold: Double) -> UltFireResult? {
    guard let tIndex = enemies.firstIndex(where: { $0.isAlive }) else { return nil }
    let belowThreshold = enemies[tIndex].hp <= enemies[tIndex].maxHP * threshold
    let damage = heroes[heroIndex].stats.attack * multiplier * (belowThreshold ? 3.0 : 1.0)
    enemies[tIndex].hp = max(0, enemies[tIndex].hp - damage)
    return UltFireResult(heroID: heroID, damage: damage, crit: false, targetID: enemies[tIndex].id)
  }

  private mutating func dealUltDamage(from heroIndex: Int, multiplier: Double) -> UltFireResult? {
    guard let tIndex = enemies.firstIndex(where: { $0.isAlive }) else { return nil }
    let raw = heroes[heroIndex].stats.attack * multiplier
    let mitigated = max(raw * 0.5, raw - enemies[tIndex].stats.defense * 0.6)
    enemies[tIndex].hp = max(0, enemies[tIndex].hp - mitigated)
    return UltFireResult(heroID: heroes[heroIndex].id, damage: mitigated, crit: false, targetID: enemies[tIndex].id)
  }
}
