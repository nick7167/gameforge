import Testing
@testable import GameCore

@Suite struct BattleEngineTests {
  var squad: [HeroDefinition] {
    [
      HeroCatalog.hero(id: "pyrelord")!,
      HeroCatalog.hero(id: "glacia")!,
      HeroCatalog.hero(id: "thornbow")!,
      HeroCatalog.hero(id: "nullreaper")!,
      HeroCatalog.hero(id: "torchbearer")!
    ]
  }

  @Test func battleRunsToOutcome() {
    var battle = BattleEngine(
      heroDefs: squad,
      config: BattleConfig(enemyStats: StatBlock(hp: 800, attack: 40, defense: 20, speed: 1.0), enemyCount: 3, isBoss: false, stagePower: 1.0),
      seed: 1
    )
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
    // Fast-forward until a damage-dealing ult is charged
    func isDamageUlt(_ effect: UltimateEffect) -> Bool {
      switch effect {
      case .damage, .chainDamage, .execute, .lifesteal: return true
      case .healAll, .shieldAll, .stunAll, .buffAttack, .freezeAll: return false
      }
    }
    var heroID: String?
    for _ in 0..<600 where heroID == nil {
      battle.tick(0.1)
      heroID = battle.heroes
        .first(where: { $0.ultCharge >= 1.0 && isDamageUlt($0.def.ultimate.effect) })?.id
    }
    #expect(heroID != nil)
    let before = battle.enemies.reduce(0) { $0 + $1.hp }
    let result = battle.fireUltimate(heroID: heroID!)
    #expect(result != nil)
    #expect(result?.damage ?? 0 > 0)
    let after = battle.enemies.reduce(0) { $0 + $1.hp }
    #expect(after < before)
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
