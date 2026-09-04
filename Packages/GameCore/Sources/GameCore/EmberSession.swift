import Foundation

/// Loot from a cleared stage (spec §5, §14). Dupes award gems at the session
/// level, so there is no faction-shard field in v1.
public struct BattleReward: Sendable {
  public let gold: Int
  public let gearDrops: [GearItem]
  public let stageCleared: StageID

  public init(gold: Int, gearDrops: [GearItem], stageCleared: StageID) {
    self.gold = gold
    self.gearDrops = gearDrops
    self.stageCleared = stageCleared
  }
}

/// The game facade (spec §14). The app layer drives this and renders its state;
/// all rules live in GameCore types.
public struct EmberSession: Sendable {
  public var profile: PlayerProfile
  public private(set) var battle: BattleEngine?
  public private(set) var lastIdleClaim: Date?

  /// Seed for battle RNG and drop rolls. Injected so tests stay deterministic;
  /// the app layer passes a time-based seed.
  private var rngSeed: UInt64

  public init(profile: PlayerProfile = .new(), rngSeed: UInt64 = 1) {
    self.profile = profile
    self.rngSeed = rngSeed
  }

  /// The stage the player is currently attempting (best cleared + 1).
  public var currentStage: StageID {
    StageProgression.next(after: profile.bestStage)
  }

  // MARK: - Battle

  /// Start a battle at the current stage with the squad in squad order.
  @discardableResult
  public mutating func startBattle() -> BattleEngine {
    let stage = currentStage
    let squadDefs = profile.squad.compactMap { id in
      profile.ownedHeroes.first { $0.definitionID == id }.map { battleDefinition(for: $0) }
    }
    var rng = SeededGenerator(seed: rngSeed &+ UInt64(stage.totalIndex))
    let engine = BattleEngine(
      heroDefs: squadDefs,
      config: BattleConfig(
        enemyStats: StageProgression.enemyStats(for: stage),
        enemyCount: StageProgression.enemyCount(for: stage),
        isBoss: stage.isBoss,
        stagePower: 1.0
      ),
      seed: rng.next()
    )
    battle = engine
    return engine
  }

  /// Catalog definition with baseStats overridden by the owned hero's computed stats.
  private func battleDefinition(for hero: OwnedHero) -> HeroDefinition {
    guard let def = HeroCatalog.hero(id: hero.definitionID) else {
      return HeroDefinition(
        id: hero.definitionID, name: hero.definitionID, faction: .ember, rarity: .common,
        role: .dps, baseStats: hero.stats(),
        ultimate: UltimateDefinition(id: "\(hero.definitionID)-ult", name: "Strike"),
        passives: [], lore: "")
    }
    return HeroDefinition(
      id: def.id, name: def.name, faction: def.faction, rarity: def.rarity, role: def.role,
      baseStats: hero.stats(), ultimate: def.ultimate, passives: def.passives, lore: def.lore)
  }

  public mutating func tickBattle(_ dt: Double) {
    battle?.tick(dt)
  }

  @discardableResult
  public mutating func fireUltimate(heroID: String) -> BattleEngine.UltFireResult? {
    battle?.fireUltimate(heroID: heroID)
  }

  /// Apply battle results. Victory: loot + advance stage. Defeat: no loot, no
  /// stage change (wall rule). Returns nil when the battle is still ongoing or lost.
  @discardableResult
  public mutating func finishBattle() -> BattleReward? {
    guard let battle, battle.outcome != .ongoing else { return nil }
    defer { self.battle = nil }
    guard battle.outcome == .victory else { return nil }

    let stage = currentStage
    let gold = StageProgression.battleReward(for: stage)
    profile.wallet.add(.gold, gold)

    var drops: [GearItem] = []
    var rng = SeededGenerator(seed: rngSeed &+ UInt64(battle.elapsed * 1000))
    if Double.random(in: 0..<1, using: &rng) < 0.4 {
      let roll = Double.random(in: 0..<1, using: &rng)
      let rarity: Rarity = switch roll {
      case ..<0.5: .common
      case ..<0.8: .rare
      case ..<0.9: .epic
      default: .legendary
      }
      drops.append(profile.equipment.generateDrop(rarity: rarity, rng: &rng))
    }

    profile.quests.record(metric: .battlesWon, amount: 1)
    profile.quests.record(metric: .stagesCleared, amount: 1)
    profile.totalBattles += 1
    profile.bestStage = stage
    return BattleReward(gold: gold, gearDrops: drops, stageCleared: stage)
  }

  // MARK: - Summons

  /// Summon heroes. Pays gems from the wallet (10× uses the discounted multi
  /// cost), then pulls cost-free. Dupe faction shards are paid out as gems
  /// (1 gem per shard — v1 simplification, ledgered here).
  @discardableResult
  public mutating func summon(
    banner: GachaEngine.BannerKind, count: Int
  ) -> [GachaEngine.PullResult]? {
    let cost = count == 10 ? GachaEngine.multiCost : GachaEngine.singleCost * count
    guard profile.wallet.spend(.gems, cost) else { return nil }

    var engine = GachaEngine(state: profile.gacha)
    var owned = Set(profile.ownedHeroes.map(\.definitionID))
    var rng = SeededGenerator(seed: rngSeed &+ UInt64(profile.totalSummons))
    var results: [GachaEngine.PullResult] = []
    for _ in 0..<count {
      let result = engine.pullFree(banner: banner, ownedHeroIDs: owned, rng: &rng)
      owned.insert(result.hero.id)
      if !result.isNew {
        profile.wallet.add(.gems, result.factionShardsAwarded)
      }
      results.append(result)
    }
    profile.gacha = engine.state
    profile.totalSummons += count
    profile.quests.record(metric: .summons, amount: count)
    return results
  }

  // MARK: - Hero progression

  /// Level up a hero with gold. Cost: 800 × current level.
  @discardableResult
  public mutating func levelUpHero(heroID: String) -> Bool {
    guard let index = profile.ownedHeroes.firstIndex(where: { $0.definitionID == heroID }) else {
      return false
    }
    let cost = Self.heroLevelCost(level: profile.ownedHeroes[index].level)
    guard profile.wallet.spend(.gold, cost) else { return false }
    profile.ownedHeroes[index].level += 1
    profile.quests.record(metric: .goldSpent, amount: cost)
    return true
  }

  public static func heroLevelCost(level: Int) -> Int { 800 * level }

  /// Equip a gear item into a hero's slot (replaces whatever was there).
  public mutating func equipGear(heroID: String, item: GearItem, slot: GearSlot) {
    guard let index = profile.ownedHeroes.firstIndex(where: { $0.definitionID == heroID }) else {
      return
    }
    profile.ownedHeroes[index].gear[slot] = item
  }

  // MARK: - Idle income

  /// Claim offline income. Returns gold awarded. When `secondsAway` is nil the
  /// elapsed time since the last claim is used (0 on the first ever claim).
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
