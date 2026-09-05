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
    // Gear drops persist to the profile inventory (review fix 2).
    #expect(session.profile.gearInventory.count == reward?.gearDrops.count ?? 0)
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
    var session = EmberSession(profile: .new(), rngSeed: 42) {
      // Overwhelm the player: a deep stage the starter squad cannot beat.
      $0.bestStage = StageID(chapter: 20, stage: 5)
    }
    session.startBattle()
    var guardCount = 0
    while session.battle?.outcome == .ongoing && guardCount < 10_000 {
      session.tickBattle(0.1)
      guardCount += 1
    }
    // Deterministic with the fixed seed: the attempt must end in defeat.
    #expect(session.battle?.outcome == .defeat)
    _ = session.finishBattle()
    // Wall rule: stage does not advance on defeat, but the attempt still counts.
    #expect(session.profile.bestStage == StageID(chapter: 20, stage: 5))
    #expect(session.profile.totalBattles == 1)
  }

  @Test func startBattleKeepsOngoingBattle() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    session.startBattle()
    session.tickBattle(0.2)
    let elapsedBefore = session.battle?.elapsed
    _ = session.startBattle()
    // An in-progress battle is never silently discarded (review fix 14).
    #expect(session.battle?.elapsed == elapsedBefore)
  }
}

@Suite struct EmberSummonTests {
  // MARK: - Summons

  @Test func summonSpendsGems() {
    var session = EmberSession(profile: .new(), rngSeed: 7) {
      $0.wallet.add(.gems, 1000)
    }
    let before = session.profile.wallet.balance(of: .gems)
    let results = session.summon(banner: .permanent, count: 1)
    #expect(results?.count == 1)
    // Ruling: dupes award no gems (faction shards deferred to Plan 2).
    #expect(session.profile.wallet.balance(of: .gems) == before - GachaEngine.singleCost)
    #expect(session.profile.totalSummons == 1)
    #expect(session.profile.quests.progress(for: "d-summon")?.count == 1)
  }

  @Test func summonRejectsInvalidCounts() {
    var session = EmberSession(profile: .new(), rngSeed: 7)
    #expect(session.summon(banner: .permanent, count: 0) == nil)
    #expect(session.summon(banner: .permanent, count: 11) == nil)
    #expect(session.profile.totalSummons == 0)
  }

  @Test func summonTenUsesMultiCost() {
    var session = EmberSession(profile: .new(), rngSeed: 7) {
      $0.wallet.add(.gems, 5000)
    }
    let before = session.profile.wallet.balance(of: .gems)
    let results = session.summon(banner: .permanent, count: 10)
    #expect(results?.count == 10)
    // 10× guarantee: at least one Rare or better.
    #expect(results!.contains { $0.hero.rarity >= .rare })
    #expect(session.profile.wallet.balance(of: .gems) == before - GachaEngine.multiCost)
    #expect(session.profile.gacha == results?.last?.state)
  }

  @Test func summonTenGuaranteesRareAcrossSeeds() {
    for seed in 1...15 {
      var session = EmberSession(profile: .new(), rngSeed: UInt64(seed)) {
        $0.wallet.add(.gems, 5000)
      }
      let results = session.summon(banner: .permanent, count: 10)
      #expect(results?.contains { $0.hero.rarity >= .rare } == true, "seed \(seed)")
    }
  }

  @Test func summonInsufficientGemsReturnsNil() {
    var session = EmberSession(profile: .new(), rngSeed: 7) {
      $0.wallet = Wallet(balances: [.gold: 2000, .gems: 99])
    }
    let results = session.summon(banner: .permanent, count: 1)
    #expect(results == nil)
    #expect(session.profile.wallet.balance(of: .gems) == 99)
    #expect(session.profile.totalSummons == 0)
  }

  // MARK: - Hero progression

  @Test func levelUpHeroCostsGold() {
    var session = EmberSession(profile: .new(), rngSeed: 42) {
      $0.wallet.add(.gold, 10_000)
    }
    let heroID = session.profile.squad[0]
    let ok = session.levelUpHero(heroID: heroID)
    #expect(ok)
    let hero = session.profile.ownedHeroes.first { $0.definitionID == heroID }
    #expect(hero?.level == 2)
    #expect(session.profile.wallet.balance(of: .gold) == 11_200)  // 2000 + 10000 - 800
    #expect(session.profile.quests.progress(for: "d-gold")?.count == 800)
  }

  @Test func levelUpFailsWhenBroke() {
    var session = EmberSession(profile: .new(), rngSeed: 42) {
      $0.wallet = Wallet(balances: [.gold: 100])
    }
    let ok = session.levelUpHero(heroID: session.profile.squad[0])
    #expect(!ok)
    let hero = session.profile.ownedHeroes.first { $0.definitionID == session.profile.squad[0] }
    #expect(hero?.level == 1)
  }

  @Test func levelUpFailsBeyondAccountLevelCap() {
    // Cap: hero level < accountLevel * 10 (XP potions deferred to Plan 2).
    var session = EmberSession(profile: .new(), rngSeed: 42) {
      $0.wallet.add(.gold, 1_000_000)
      $0.accountLevel = 1
      $0.ownedHeroes[0].level = 10
    }
    let ok = session.levelUpHero(heroID: session.profile.squad[0])
    #expect(!ok)
    #expect(session.profile.ownedHeroes[0].level == 10)
    // Failed level-up spends nothing.
    #expect(session.profile.wallet.balance(of: .gold) == 1_002_000)
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
    let equipped = session.equipGear(heroID: heroID, item: item, slot: .weapon)
    #expect(equipped)
    let after = session.profile.ownedHeroes.first { $0.definitionID == heroID }?.stats().attack ?? 0
    #expect(after == before + 50)
  }

  @Test func equipGearValidatesSlotAndHero() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    let item = GearItem(slot: .weapon, rarity: .common, mainStat: GearStat(kind: .attack, value: 50))
    // Slot/item mismatch fails.
    let slotMismatch = session.equipGear(heroID: session.profile.squad[0], item: item, slot: .armor)
    #expect(!slotMismatch)
    // Unknown hero fails.
    let unknownHero = session.equipGear(heroID: "nonexistent", item: item, slot: .weapon)
    #expect(!unknownHero)
  }

  @Test func enhanceGearSpendsGoldAndLevelsItem() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    let heroID = session.profile.squad[0]
    let item = GearItem(slot: .weapon, rarity: .common, mainStat: GearStat(kind: .attack, value: 50))
    let equipped = session.equipGear(heroID: heroID, item: item, slot: .weapon)
    #expect(equipped)
    // enhanceCost(level 0) = 500 of the starting 2000 gold.
    let enhanced = session.enhanceGear(heroID: heroID, slot: .weapon)
    #expect(enhanced)
    #expect(session.profile.wallet.balance(of: .gold) == 1500)
    let hero = session.profile.ownedHeroes.first { $0.definitionID == heroID }
    #expect(hero?.gear[.weapon]?.enhanceLevel == 1)
    #expect(session.profile.quests.progress(for: "d-enhance")?.count == 1)
  }

  @Test func enhanceGearFailsWithoutGold() {
    var session = EmberSession(profile: .new(), rngSeed: 42) {
      $0.wallet = Wallet(balances: [.gold: 100])
    }
    let heroID = session.profile.squad[0]
    let item = GearItem(slot: .weapon, rarity: .common, mainStat: GearStat(kind: .attack, value: 50))
    let equipped = session.equipGear(heroID: heroID, item: item, slot: .weapon)
    #expect(equipped)
    let enhanced = session.enhanceGear(heroID: heroID, slot: .weapon)
    #expect(!enhanced)
    let equippedHero = session.profile.ownedHeroes.first { $0.definitionID == heroID }
    #expect(equippedHero?.gear[.weapon]?.enhanceLevel == 0)
    #expect(session.profile.quests.progress(for: "d-enhance") == nil)
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

  @Test func equipSwapsWithInventory() {
    let rareItem = GearItem(slot: .weapon, rarity: .rare, mainStat: GearStat(kind: .attack, value: 10))
    let epicItem = GearItem(slot: .weapon, rarity: .epic, mainStat: GearStat(kind: .attack, value: 30))
    var session = EmberSession(profile: .new(), rngSeed: 42) {
      $0.addToGearInventory([rareItem, epicItem])
    }
    let heroID = session.profile.squad[0]
    session.equipGear(heroID: heroID, item: rareItem, slot: .weapon)
    #expect(session.profile.gearInventory.count == 1) // epic still in inventory
    session.equipGear(heroID: heroID, item: epicItem, slot: .weapon)
    #expect(session.profile.gearInventory.count == 1) // old weapon returned
    #expect(session.profile.gearInventory[0].rarity == .rare)
  }

  // MARK: - Squad management

  @Test func setSquadValidates() {
    var session = EmberSession()
    let owned = session.profile.ownedHeroes.map(\.definitionID)
    session.setSquad(Array(owned.prefix(2)))
    #expect(session.profile.squad.count == 5) // rejected: too few
    session.setSquad(owned)
    #expect(session.profile.squad == owned)
    session.setSquad(owned.dropFirst().map { $0 } + ["nonexistent"])
    #expect(session.profile.squad == owned) // rejected: unknown hero
  }

  // MARK: - Idle income

  @Test func idleClaimGrantsGold() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    let gold = session.claimIdle()
    #expect(gold >= 0)
  }

  @Test func idleClaimZeroGoldSkipsQuestMetric() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    // First-ever claim with no elapsed time awards 0 gold → no quest metric.
    let gold = session.claimIdle(secondsAway: 0)
    #expect(gold == 0)
    #expect(session.profile.quests.progress(for: "d-idle") == nil)
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
    // New fields decode with defaults on pre-existing profiles.
    #expect(decoded.gearInventory.isEmpty)
    #expect(decoded.lastIdleClaim == nil)
  }

  @Test func profileRoundTripsGearAndIdleClaim() throws {
    var profile = PlayerProfile.new()
    let item = GearItem(slot: .weapon, rarity: .rare, mainStat: GearStat(kind: .attack, value: 50))
    profile.addToGearInventory([item])
    let claim = Date(timeIntervalSince1970: 1_700_000_000)
    profile.lastIdleClaim = claim
    let data = try JSONEncoder().encode(profile)
    let decoded = try JSONDecoder().decode(PlayerProfile.self, from: data)
    #expect(decoded.gearInventory.count == 1)
    #expect(decoded.gearInventory.first?.id == item.id)
    #expect(decoded.lastIdleClaim == claim)
  }

  @Test func battleDropsPersistToGearInventory() {
    var sawDrop = false
    for seed in 1...20 {
      var session = EmberSession(profile: .new(), rngSeed: UInt64(seed))
      session.startBattle()
      var ticks = 0
      while session.battle?.outcome == .ongoing && ticks < 10_000 {
        session.tickBattle(0.1)
        ticks += 1
      }
      guard session.battle?.outcome == .victory, let reward = session.finishBattle() else { continue }
      #expect(session.profile.gearInventory.count == reward.gearDrops.count)
      if !reward.gearDrops.isEmpty { sawDrop = true }
    }
    // 40% drop chance per victory: at least one of 20 seeded victories must drop.
    #expect(sawDrop)
  }

  // MARK: - Profile helpers (added for the app-layer facade)

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
}
