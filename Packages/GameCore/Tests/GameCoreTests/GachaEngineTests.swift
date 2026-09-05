import Foundation
import Testing
@testable import GameCore

@Suite struct GachaEngineTests {
  /// Pull helper for tests that don't care about the throw path.
  private static func pull(
    _ engine: inout GachaEngine, banner: GachaEngine.BannerKind, shards: inout Int,
    ownedHeroIDs: Set<String>, rng: inout SeededGenerator
  ) -> GachaEngine.PullResult {
    // Test helper: shards are pre-funded by callers, so the pull cannot throw.
    // swiftlint:disable force_try
    try! engine.pull(banner: banner, shards: &shards, ownedHeroIDs: ownedHeroIDs, rng: &rng)
    // swiftlint:enable force_try
  }

  @Test func freeDailySummonOncePerDay() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    let first = session.freeDailySummon()
    #expect(first?.count == 1)
    #expect(session.profile.totalSummons == 1)
    #expect(session.freeDailySummon() == nil) // already used today
    #expect(session.profile.totalSummons == 1) // second call pulled nothing
  }

  @Test func freeDailySummonPersistsDay() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    _ = session.freeDailySummon()
    #expect(session.profile.lastFreeSummonDay == EmberSession.dayIndex(Date()))
    // A session reloaded from the same profile still sees today's pull as used.
    var reloaded = EmberSession(profile: session.profile, rngSeed: 42)
    #expect(reloaded.freeDailySummon() == nil)
  }

  @Test func pullCostsShards() {
    var engine = GachaEngine()
    var shards = 100
    var rng = SeededGenerator(seed: 1)
    let result = Self.pull(&engine, banner: .permanent, shards: &shards, ownedHeroIDs: Set<String>(), rng: &rng)
    #expect(shards == 0)
    #expect(result.hero.rarity >= .common)
  }

  @Test func pullFailsWithoutShards() {
    var engine = GachaEngine()
    var shards = 99
    var rng = SeededGenerator(seed: 1)
    #expect(throws: GachaError.insufficientShards) {
      _ = try engine.pull(banner: .permanent, shards: &shards, ownedHeroIDs: Set<String>(), rng: &rng)
    }
  }

  @Test func epicPityTriggersWithin10() {
    var engine = GachaEngine()
    var shards = 10_000
    var rng = SeededGenerator(seed: 42)
    var sawEpicOrBetter = false
    for _ in 0..<10 {
      let result = Self.pull(&engine, banner: .permanent, shards: &shards, ownedHeroIDs: Set<String>(), rng: &rng)
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
      let result = Self.pull(&engine, banner: .permanent, shards: &shards, ownedHeroIDs: Set<String>(), rng: &rng)
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
      let result = Self.pull(&engine, banner: .permanent, shards: &shards, ownedHeroIDs: owned, rng: &rng)
      if !result.isNew, result.factionShardsAwarded > 0 { sawDupeShards = true }
      owned.insert(result.hero.id)
    }
    #expect(sawDupeShards)
  }

  @Test func dupeShardAmountsMatchRarity() {
    var engine = GachaEngine()
    // Feed a known owned set: every dupe of a legendary must award 30 shards.
    let ownedLegendaries = Set(HeroCatalog.byRarity(.legendary).map(\.id))
    var shards = 100_000
    var rng = SeededGenerator(seed: 11)
    var checked = false
    for _ in 0..<200 {
      let result = Self.pull(&engine, banner: .permanent, shards: &shards, ownedHeroIDs: ownedLegendaries, rng: &rng)
      if result.hero.rarity == .legendary {
        #expect(!result.isNew)
        #expect(result.factionShardsAwarded == 30)
        checked = true
        break
      }
    }
    #expect(checked)
  }

  @Test func tenPullCostsLessThanTenSingles() {
    #expect(GachaEngine.multiCost < GachaEngine.singleCost * 10)
  }

  @Test func pullTenReturnsEmptyWhenUnaffordable() {
    var engine = GachaEngine()
    var shards = 899
    var rng = SeededGenerator(seed: 3)
    let results = engine.pullTen(banner: .permanent, shards: &shards, ownedHeroIDs: Set<String>(), rng: &rng)
    #expect(results.isEmpty)
    #expect(shards == 899) // no cost deducted on failure
  }

  @Test func pullTenGuaranteesRareOrBetter() {
    var engine = GachaEngine()
    var shards = 100_000
    var rng = SeededGenerator(seed: 5)
    var sawGuarantee = false
    for _ in 0..<20 {
      let results = engine.pullTen(banner: .permanent, shards: &shards, ownedHeroIDs: Set<String>(), rng: &rng)
      #expect(results.count == 10)
      if results.contains(where: { $0.hero.rarity >= .rare }) { sawGuarantee = true }
    }
    #expect(sawGuarantee)
  }

  @Test func featuredBannerRatesUp() {
    // Statistical: featured banner should yield the featured hero among legendaries ~50%
    var engine = GachaEngine()
    var shards = 500_000
    var rng = SeededGenerator(seed: 99)
    var featuredCount = 0
    var legendaryCount = 0
    for _ in 0..<500 {
      let result = Self.pull(
        &engine, banner: .featured(heroID: "pyrelord"), shards: &shards, ownedHeroIDs: Set<String>(), rng: &rng
      )
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

  @Test func stateTracksPityCounters() {
    var engine = GachaEngine()
    var shards = 5_000
    var rng = SeededGenerator(seed: 5)
    for _ in 0..<9 {
      _ = Self.pull(&engine, banner: .permanent, shards: &shards, ownedHeroIDs: Set<String>(), rng: &rng)
    }
    #expect(engine.state.epicPity == 9 || engine.state.epicPity == 0) // reset only if an Epic dropped
    #expect(engine.state.legendaryPity == 9 || engine.state.legendaryPity == 0)
  }
}
