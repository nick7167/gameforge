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
    #expect(sum.hp == 150 && sum.attack == 15 && sum.critDamage == 2.0) // 1.5 + 0.5
  }

  @Test func walletSpendFailsWhenInsufficient() {
    var wallet = Wallet()
    wallet.add(.gold, 100)
    #expect(wallet.spend(.gold, 200) == false)
    #expect(wallet.balance(of: .gold) == 100) // failed spend must not mutate balance
    #expect(wallet.spend(.gold, 50) == true)
    #expect(wallet.balance(of: .gold) == 50)
  }
}
