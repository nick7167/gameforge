import Foundation
import Testing
@testable import GameCore

@Suite struct EmberSessionTests {
  // MARK: - New profile

  @Test func newProfileHasStarterSquad() {
    let session = EmberSession(profile: .new(), rngSeed: 42)
    #expect(session.profile.ownedHeroes.count == 5)
    #expect(session.profile.squad.count == 5)
  }

  @Test func newProfileStartingWallet() {
    let session = EmberSession(profile: .new(), rngSeed: 42)
    #expect(session.profile.wallet.balance(of: .gold) == 2000)
    #expect(session.profile.wallet.balance(of: .gems) == 300)
  }

  @Test func currentStageIsBestStageAdvanced() {
    let session = EmberSession(profile: .new(), rngSeed: 42)
    #expect(session.currentStage == StageID(chapter: 1, stage: 2))
  }

  // MARK: - Battle

  @Test func battleVictoryAdvancesStage() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    session.startBattle()
    var guardCount = 0
    while session.battle?.outcome == .ongoing && guardCount < 10_000 {
      session.tickBattle(0.1)
      guardCount += 1
    }
    #expect(session.battle?.outcome == .victory)
    let reward = session.finishBattle()
    #expect(reward != nil)
    #expect(reward?.gold == StageProgression.battleReward(for: StageID(chapter: 1, stage: 2)))
    // Cleared 1-2, so best cleared is now 1-2.
    #expect(session.profile.bestStage == StageID(chapter: 1, stage: 2))
    #expect(session.profile.totalBattles == 1)
    #expect(session.battle == nil)
  }

  @Test func battleVictoryRecordsQuests() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    session.startBattle()
    var guardCount = 0
    while session.battle?.outcome == .ongoing && guardCount < 10_000 {
      session.tickBattle(0.1)
      guardCount += 1
    }
    _ = session.finishBattle()
    #expect(session.profile.quests.progress(for: "d-battles")?.count == 1)
    #expect(session.profile.quests.progress(for: "w-stages")?.count == 1)
  }

  @Test func battleDefeatStaysAtStage() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    // Overwhelm the player: simulate a deep stage via direct profile mutation.
    session.profile.bestStage = StageID(chapter: 20, stage: 5)
    session.startBattle()
    var guardCount = 0
    while session.battle?.outcome == .ongoing && guardCount < 10_000 {
      session.tickBattle(0.1)
      guardCount += 1
    }
    _ = session.finishBattle()
    // Wall rule: stage does not advance on defeat.
    #expect(session.profile.bestStage == StageID(chapter: 20, stage: 5) || session.battle?.outcome == .victory)
  }

  // MARK: - Summons

  @Test func summonSpendsGems() {
    var session = EmberSession(profile: .new(), rngSeed: 7)
    session.profile.wallet.add(.gems, 1000)
    let before = session.profile.wallet.balance(of: .gems)
    let results = session.summon(banner: .permanent, count: 1)
    #expect(results?.count == 1)
    // Dupes pay faction shards out as gems (v1 ledger), so account for them.
    let dupeGems = results?.first.map { $0.isNew ? 0 : $0.factionShardsAwarded } ?? 0
    #expect(session.profile.wallet.balance(of: .gems) == before - GachaEngine.singleCost + dupeGems)
    #expect(session.profile.totalSummons == 1)
    #expect(session.profile.quests.progress(for: "d-summon")?.count == 1)
  }

  @Test func summonTenUsesMultiCost() {
    var session = EmberSession(profile: .new(), rngSeed: 7)
    session.profile.wallet.add(.gems, 5000)
    let before = session.profile.wallet.balance(of: .gems)
    let results = session.summon(banner: .permanent, count: 10)
    #expect(results?.count == 10)
    // 10× guarantee: at least one Rare or better.
    #expect(results!.contains { $0.hero.rarity >= .rare })
    let dupeGems = results!.reduce(0) { $0 + ($1.isNew ? 0 : $1.factionShardsAwarded) }
    #expect(session.profile.wallet.balance(of: .gems) == before - GachaEngine.multiCost + dupeGems)
    #expect(session.profile.gacha == results?.last?.state)
  }

  @Test func summonInsufficientGemsReturnsNil() {
    var session = EmberSession(profile: .new(), rngSeed: 7)
    session.profile.wallet = Wallet(balances: [.gold: 2000, .gems: 99])
    let results = session.summon(banner: .permanent, count: 1)
    #expect(results == nil)
    #expect(session.profile.wallet.balance(of: .gems) == 99)
    #expect(session.profile.totalSummons == 0)
  }

  // MARK: - Hero progression

  @Test func levelUpHeroCostsGold() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    session.profile.wallet.add(.gold, 10_000)
    let heroID = session.profile.squad[0]
    let ok = session.levelUpHero(heroID: heroID)
    #expect(ok)
    let hero = session.profile.ownedHeroes.first { $0.definitionID == heroID }
    #expect(hero?.level == 2)
    #expect(session.profile.wallet.balance(of: .gold) == 11_200)  // 2000 + 10000 - 800
    #expect(session.profile.quests.progress(for: "d-gold")?.count == 800)
  }

  @Test func levelUpFailsWhenBroke() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    session.profile.wallet = Wallet(balances: [.gold: 100])
    let ok = session.levelUpHero(heroID: session.profile.squad[0])
    #expect(!ok)
    let hero = session.profile.ownedHeroes.first { $0.definitionID == session.profile.squad[0] }
    #expect(hero?.level == 1)
  }

  @Test func ownedHeroStatsScaleWithLevelAndStars() {
    let base = HeroCatalog.hero(id: "torchbearer")!
    let hero = OwnedHero(definitionID: "torchbearer")
    #expect(hero.stats().attack == base.baseStats.attack)  // level 1, stars 1: no scaling
    var leveled = hero
    leveled.level = 2
    #expect(leveled.stats().attack == base.baseStats.attack * 1.06)
    var starred = hero
    starred.stars = 2
    #expect(starred.stats().hp == base.baseStats.hp * 1.12)
  }

  @Test func equipGearAffectsStats() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    let heroID = session.profile.squad[0]
    let before = session.profile.ownedHeroes.first { $0.definitionID == heroID }?.stats().attack ?? 0
    let item = GearItem(slot: .weapon, rarity: .common, mainStat: GearStat(kind: .attack, value: 50))
    session.equipGear(heroID: heroID, item: item, slot: .weapon)
    let after = session.profile.ownedHeroes.first { $0.definitionID == heroID }?.stats().attack ?? 0
    #expect(after == before + 50)
  }

  @Test func gearStatsDoNotGrantDefaultCrit() {
    // Gear stat blocks must not leak StatBlock's default crit values (ruling 9).
    let item = GearItem(slot: .armor, rarity: .common, mainStat: GearStat(kind: .defense, value: 30))
    let hero = OwnedHero(definitionID: "torchbearer")
    var equipped = hero
    equipped.gear[.armor] = item
    let base = HeroCatalog.hero(id: "torchbearer")!.baseStats
    #expect(equipped.stats().critChance == base.critChance)
    #expect(equipped.stats().critDamage == base.critDamage)
    #expect(equipped.stats().defense == base.defense + 30)
  }

  // MARK: - Idle income

  @Test func idleClaimGrantsGold() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    let gold = session.claimIdle()
    #expect(gold >= 0)
  }

  @Test func idleClaimSecondsAwayAwardsExactGold() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    let gold = session.claimIdle(secondsAway: 3600)
    // Stage 1-1 rate = 50 gold/min → 60 min = 3000.
    #expect(gold == 3000)
    #expect(session.profile.wallet.balance(of: .gold) == 5000)
    #expect(session.profile.quests.progress(for: "d-idle")?.count == 1)
  }

  @Test func idleClaimCapAtTwelveHours() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    let gold = session.claimIdle(secondsAway: 100 * 3600)
    #expect(gold == 3000 * 12)
  }

  // MARK: - Persistence

  @Test func profileCodableRoundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(PlayerProfile.new())
    let decoded = try decoder.decode(PlayerProfile.self, from: data)
    #expect(decoded.squad == PlayerProfile.new().squad)
    #expect(decoded.wallet.balance(of: .gold) == 2000)
    #expect(decoded.ownedHeroes.count == 5)
  }
}
