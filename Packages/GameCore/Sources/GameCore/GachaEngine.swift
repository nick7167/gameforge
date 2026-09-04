import Foundation

/// Persistent gacha counters (pity). Persist with the player profile.
public struct GachaState: Sendable, Codable, Equatable {
  public var epicPity: Int
  public var legendaryPity: Int
  public var pullsSinceFeaturedLegendary: Int

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
///
/// All rolls go through `SeededGenerator` so summons are deterministic and replayable.
public struct GachaEngine: Sendable {
  public static let singleCost = 100
  public static let multiCost = 900

  private static let legendaryRate = 0.02
  private static let epicRate = 0.10
  private static let rareRate = 0.30
  // common = remainder (0.58)

  private static let epicPityLimit = 10
  private static let legendaryPityLimit = 60

  /// Chance that a rolled Legendary on a featured banner is the featured hero.
  private static let featuredLegendaryChance = 0.5

  /// Cap on re-rolls when forcing a minimum rarity (10×-pull guarantee).
  private static let maxRarityRerolls = 20

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
    public let state: GachaState
  }

  /// Pull once. Throws `GachaError.insufficientShards` if the player can't afford it.
  public mutating func pull(
    banner: BannerKind, shards: inout Int, ownedHeroIDs: Set<String>, rng: inout SeededGenerator
  ) throws -> PullResult {
    guard shards >= Self.singleCost else { throw GachaError.insufficientShards }
    shards -= Self.singleCost
    return pullRaw(banner: banner, ownedHeroIDs: ownedHeroIDs, rng: &rng, minimumRarity: nil)
  }

  /// 10× pull: costs `multiCost`, guarantees at least one Rare. Returns `[]` if unaffordable.
  public mutating func pullTen(
    banner: BannerKind, shards: inout Int, ownedHeroIDs: Set<String>, rng: inout SeededGenerator
  ) -> [PullResult] {
    guard shards >= Self.multiCost else { return [] }
    shards -= Self.multiCost
    var results: [PullResult] = []
    for index in 0..<10 {
      let needsGuarantee = index == 9 && !results.contains { $0.hero.rarity >= .rare }
      let result = pullRaw(
        banner: banner, ownedHeroIDs: ownedHeroIDs, rng: &rng, minimumRarity: needsGuarantee ? .rare : nil
      )
      results.append(result)
    }
    return results
  }

  /// Cost-free pull: identical to `pull` minus shard handling. Used by the
  /// session facade, which pays the gem cost from the wallet up front. Pass
  /// `minimumRarity` to force a rarity floor (10×-pull guarantee on the last pull).
  public mutating func pullFree(
    banner: BannerKind, ownedHeroIDs: Set<String>, rng: inout SeededGenerator,
    minimumRarity: Rarity? = nil
  ) -> PullResult {
    pullRaw(banner: banner, ownedHeroIDs: ownedHeroIDs, rng: &rng, minimumRarity: minimumRarity)
  }

  /// Shared pull logic (no cost handling). Pity counters increment before the roll;
  /// a Legendary grant resets both counters, an Epic grant resets the Epic counter only.
  mutating func pullRaw(
    banner: BannerKind, ownedHeroIDs: Set<String>, rng: inout SeededGenerator, minimumRarity: Rarity?
  ) -> PullResult {
    state.epicPity += 1
    state.legendaryPity += 1

    var rarity = rollRarity(rng: &rng)
    var attempts = 0
    while let minimum = minimumRarity, rarity < minimum, attempts < Self.maxRarityRerolls {
      rarity = rollRarity(rng: &rng)
      attempts += 1
    }

    switch rarity {
    case .legendary:
      state.legendaryPity = 0
      state.epicPity = 0
    case .epic:
      state.epicPity = 0
    case .rare, .common:
      break
    }

    let hero = pickHero(rarity: rarity, banner: banner, rng: &rng)
    if case .featured = banner, rarity == .legendary, hero.id == featuredHeroID(banner) {
      state.pullsSinceFeaturedLegendary = 0
    } else {
      state.pullsSinceFeaturedLegendary += 1
    }

    let isNew = !ownedHeroIDs.contains(hero.id)
    let factionShards = isNew ? 0 : Self.dupeShards[hero.rarity] ?? 0
    return PullResult(hero: hero, isNew: isNew, factionShardsAwarded: factionShards, state: state)
  }

  /// One rarity roll, pity included.
  private func rollRarity(rng: inout SeededGenerator) -> Rarity {
    let roll = Double.random(in: 0..<1, using: &rng)
    if state.legendaryPity >= Self.legendaryPityLimit || roll < Self.legendaryRate {
      return .legendary
    }
    if state.epicPity >= Self.epicPityLimit || roll < Self.legendaryRate + Self.epicRate {
      return .epic
    }
    if roll < Self.legendaryRate + Self.epicRate + Self.rareRate {
      return .rare
    }
    return .common
  }

  private func featuredHeroID(_ banner: BannerKind) -> String? {
    if case .featured(let heroID) = banner { return heroID }
    return nil
  }

  /// Pick a hero of the given rarity. On a featured banner, a rolled Legendary has a
  /// 50% chance to be the featured hero (when that hero exists at Legendary rarity).
  private func pickHero(rarity: Rarity, banner: BannerKind, rng: inout SeededGenerator) -> HeroDefinition {
    if rarity == .legendary, let featuredID = featuredHeroID(banner),
      let featured = HeroCatalog.hero(id: featuredID), featured.rarity == .legendary,
      Double.random(in: 0..<1, using: &rng) < Self.featuredLegendaryChance {
      return featured
    }
    let pool = HeroCatalog.byRarity(rarity)
    let index = Int(Double.random(in: 0..<1, using: &rng) * Double(pool.count))
    return pool[index]
  }

  /// Dupe → faction shards (spec §6.2).
  private static let dupeShards: [Rarity: Int] = [
    .common: 1, .rare: 3, .epic: 10, .legendary: 30
  ]
}
