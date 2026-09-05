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
  public private(set) var profile: PlayerProfile
  public private(set) var battle: BattleEngine?

  /// Seed for battle RNG and drop rolls. Injected so tests stay deterministic;
  /// the app layer passes a time-based seed.
  private var rngSeed: UInt64

  public init(profile: PlayerProfile = .new(), rngSeed: UInt64 = 1) {
    self.profile = profile
    self.rngSeed = rngSeed
  }

  /// Internal test-fixture entry point: builds a session and lets the caller
  /// shape the profile directly. App code cannot reach this (internal only);
  /// tests use `@testable import GameCore`.
  init(profile: PlayerProfile, rngSeed: UInt64, configure: (inout PlayerProfile) -> Void) {
    var configured = profile
    configure(&configured)
    self.profile = configured
    self.rngSeed = rngSeed
  }

  /// The stage the player is currently attempting (best cleared + 1).
  public var currentStage: StageID {
    StageProgression.next(after: profile.bestStage)
  }

  // MARK: - Battle

  /// Start a battle at the current stage with the squad in squad order. A
  /// no-op when a battle is already in progress (an ongoing fight is never
  /// silently discarded).
  @discardableResult
  public mutating func startBattle() -> BattleEngine? {
    guard battle == nil || battle?.outcome != .ongoing else { return battle }
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
      assertionFailure("Unknown hero id \(hero.definitionID) in catalog")
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

    // Any finished battle counts, win or lose.
    profile.totalBattles += 1

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
    profile.addToGearInventory(drops)

    profile.quests.record(metric: .battlesWon, amount: 1)
    profile.quests.record(metric: .stagesCleared, amount: 1)
    profile.bestStage = stage
    return BattleReward(gold: gold, gearDrops: drops, stageCleared: stage)
  }

  // MARK: - Summons

  /// Summon heroes. Pays gems from the wallet (10× uses the discounted multi
  /// cost), then pulls cost-free. On a 10× summon the last pull is upgraded to
  /// Rare+ when the first nine produced nothing better than Common (guarantee).
  @discardableResult
  public mutating func summon(
    banner: GachaEngine.BannerKind, count: Int
  ) -> [GachaEngine.PullResult]? {
    guard (1...10).contains(count) else { return nil }
    let cost = count == 10 ? GachaEngine.multiCost : GachaEngine.singleCost * count
    guard profile.wallet.spend(.gems, cost) else { return nil }
    return performSummons(banner: banner, count: count)
  }

  /// The daily free single summon (spec §6.2). Costs nothing; tracks the last
  /// used day on the profile so it survives relaunch. Returns nil when the
  /// free pull was already used today.
  @discardableResult
  public mutating func freeDailySummon() -> [GachaEngine.PullResult]? {
    let today = Self.dayIndex(Date())
    if profile.lastFreeSummonDay == today { return nil }
    guard let results = performSummons(banner: .permanent, count: 1) else { return nil }
    profile.lastFreeSummonDay = today
    return results
  }

  /// Day index used for the free-pull check. Ordinality within the era is a
  /// monotonically increasing day count, so it never repeats across years.
  public static func dayIndex(_ date: Date) -> Int {
    Calendar(identifier: .gregorian).ordinality(of: .day, in: .era, for: date) ?? 0
  }

  /// Shared pull loop (no cost handling). Caller pays the gem cost first.
  /// On a 10× summon the last pull gets the Rare+ guarantee when needed.
  private mutating func performSummons(
    banner: GachaEngine.BannerKind, count: Int
  ) -> [GachaEngine.PullResult]? {
    guard (1...10).contains(count) else { return nil }
    var engine = GachaEngine(state: profile.gacha)
    var owned = Set(profile.ownedHeroes.map(\.definitionID))
    var rng = SeededGenerator(seed: rngSeed &+ UInt64(profile.totalSummons))
    var results: [GachaEngine.PullResult] = []
    for index in 0..<count {
      let needsGuarantee =
        index == count - 1 && count == 10
        && !results.contains { $0.hero.rarity >= .rare }
      let result = engine.pullFree(
        banner: banner, ownedHeroIDs: owned, rng: &rng, minimumRarity: needsGuarantee ? .rare : nil)
      owned.insert(result.hero.id)
      // Ruling: faction shards from dupes deferred to Plan 2 persistence pass.
      results.append(result)
    }
    profile.gacha = engine.state
    profile.totalSummons += count
    profile.quests.record(metric: .summons, amount: count)
    return results
  }

  // MARK: - Hero progression

  /// Level up a hero with gold. Cost: 800 × current level. Level is capped at
  /// 10× account level (XP potions deferred to Plan 2).
  @discardableResult
  public mutating func levelUpHero(heroID: String) -> Bool {
    guard let index = profile.ownedHeroes.firstIndex(where: { $0.definitionID == heroID }) else {
      return false
    }
    guard profile.ownedHeroes[index].level < profile.accountLevel * 10 else { return false }
    let cost = Self.heroLevelCost(level: profile.ownedHeroes[index].level)
    guard profile.wallet.spend(.gold, cost) else { return false }
    profile.ownedHeroes[index].level += 1
    profile.quests.record(metric: .goldSpent, amount: cost)
    return true
  }

  public static func heroLevelCost(level: Int) -> Int { 800 * level }

  /// Replace the squad. Validates count/uniqueness/ownership; no-op on invalid input.
  public mutating func setSquad(_ ids: [String]) {
    guard ids.count == 5, Set(ids).count == 5,
      ids.allSatisfy({ id in profile.ownedHeroes.contains { $0.definitionID == id } })
    else { return }
    profile.squad = ids
  }

  /// Equip a gear item into a hero's slot (replaces whatever was there).
  /// The item leaves the gear inventory; a previously equipped item in the
  /// same slot returns to the inventory. Fails on unknown heroes or a
  /// slot/item mismatch.
  @discardableResult
  public mutating func equipGear(heroID: String, item: GearItem, slot: GearSlot) -> Bool {
    guard profile.ownedHeroes.contains(where: { $0.definitionID == heroID }) else { return false }
    guard item.slot == slot else { return false }
    guard let index = profile.ownedHeroes.firstIndex(where: { $0.definitionID == heroID }) else {
      return false
    }
    // Return whatever was in the slot back to the inventory.
    if let previous = profile.ownedHeroes[index].gear[slot] {
      profile.addToGearInventory([previous])
    }
    profile.ownedHeroes[index].gear[slot] = item
    profile.removeFromGearInventory(item.id)
    return true
  }

  /// Enhance the hero's equipped item in `slot` by one level, spending gold.
  /// Returns false on unknown hero, empty slot, or insufficient gold.
  @discardableResult
  public mutating func enhanceGear(heroID: String, slot: GearSlot) -> Bool {
    guard let index = profile.ownedHeroes.firstIndex(where: { $0.definitionID == heroID }),
      var item = profile.ownedHeroes[index].gear[slot]
    else { return false }
    let cost = EquipmentSystem.enhanceCost(level: item.enhanceLevel)
    guard profile.wallet.balance(of: .gold) >= cost else { return false }
    var gold = profile.wallet.balance(of: .gold)
    let ok = profile.equipment.enhance(item: &item, gold: &gold)
    guard ok else { return false }
    profile.ownedHeroes[index].gear[slot] = item
    profile.wallet.spend(.gold, cost)
    profile.quests.record(metric: .enhances, amount: 1)
    return true
  }

  // MARK: - Profile helpers

  /// Claim a completed quest's rewards (spec §9). Returns false when the quest
  /// is unknown, incomplete, or already claimed. Rewards go to `profile.wallet`.
  @discardableResult
  public mutating func claimQuest(questID: String) -> Bool {
    profile.quests.claim(questID: questID, wallet: &profile.wallet)
  }

  /// Rename the player (profile screen).
  public mutating func renamePlayer(_ name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    profile.name = String(trimmed.prefix(20))
  }

  /// Grant gems (IAP fulfillment, rewards). Server-validated later (Plan 3).
  public mutating func grantGems(_ amount: Int) {
    grantCurrency(.gems, amount)
  }

  /// Grant any currency (IAP fulfillment, test hooks, market fulfillment).
  public mutating func grantCurrency(_ currency: Currency, _ amount: Int) {
    guard amount > 0 else { return }
    profile.wallet.add(currency, amount)
  }

  // MARK: - Market

  /// Whether today's free Market item is still unclaimed.
  public func freeMarketClaimedToday(date: Date = Date()) -> Bool {
    profile.lastFreeMarketClaimDay == Self.dayIndex(date)
  }

  /// Buy a market entry. Spends the entry's currency, grants the item/gold/gems.
  /// Free items (price 0) cost nothing but can only be claimed once per day
  /// (tracked via `profile.lastFreeMarketClaimDay`).
  @discardableResult
  public mutating func buyMarket(entryID: String, date: Date = Date()) -> Bool {
    guard let entry = MarketSystem.dailyStock(for: date).first(where: { $0.id == entryID }) else {
      return false
    }
    if entry.price == 0 {
      let today = Self.dayIndex(date)
      guard profile.lastFreeMarketClaimDay != today else { return false }
      profile.lastFreeMarketClaimDay = today
    } else {
      guard profile.wallet.spend(entry.currency, entry.price) else { return false }
    }
    switch entry.kind {
    case .gearBox(let rarity):
      var rng = SeededGenerator(
        seed: rngSeed &+ UInt64(profile.gearInventory.count) &+ UInt64(Self.dayIndex(date)))
      let drop = profile.equipment.generateDrop(rarity: rarity, rng: &rng)
      profile.addToGearInventory([drop])
    case .goldPack(let amount):
      profile.wallet.add(.gold, amount)
    case .xpPotion(let amount):
      profile.accountLevel += max(1, amount / 100)  // v1 placeholder progression
    case .gemBundle(let amount):
      profile.wallet.add(.gems, amount)
    }
    return true
  }

  // MARK: - Idle income

  /// Claim offline income. Returns gold awarded. When `secondsAway` is nil the
  /// elapsed time since the last claim is used (0 on the first ever claim).
  /// The timestamp lives on the profile so offline income survives relaunch.
  @discardableResult
  public mutating func claimIdle(secondsAway: Double? = nil) -> Int {
    let elapsed: Double
    if let secondsAway {
      elapsed = secondsAway
    } else if let last = profile.lastIdleClaim {
      elapsed = Date().timeIntervalSince(last)
    } else {
      elapsed = 0
    }
    let (gold, _) = IdleIncome.earnings(bestStage: profile.bestStage, secondsAway: elapsed)
    profile.wallet.add(.gold, gold)
    profile.lastIdleClaim = Date()
    if gold > 0 {
      profile.quests.record(metric: .idleClaims, amount: 1)
    }
    return gold
  }
}
