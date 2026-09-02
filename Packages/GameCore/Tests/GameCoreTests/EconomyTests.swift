import Testing
@testable import GameCore

@Suite struct EconomyTests {
  @Test func rentIsOneCoinPerDistrict() {
    var economy = Economy(startingCoins: 0)
    let earned = economy.earnRent(districtsHoused: 4, perfectStreak: 0)
    #expect(earned == 4)
    #expect(economy.coins == 4)
  }

  @Test func perfectStreakMultipliesBonus() {
    var economy = Economy(startingCoins: 0)
    // streak 1 → ×1.0 → bonus 5; streak 3 → ×2.0 → bonus 10
    #expect(economy.earnRent(districtsHoused: 0, perfectStreak: 1) == 5)
    var e2 = Economy(startingCoins: 0)
    #expect(e2.earnRent(districtsHoused: 0, perfectStreak: 3) == 10)
  }

  @Test func spendRequiresFunds() {
    var economy = Economy(startingCoins: 10)
    #expect(economy.spend(5) == true)
    #expect(economy.coins == 5)
    #expect(economy.spend(10) == false)
    #expect(economy.coins == 5, "failed purchase must not deduct")
  }

  @Test func buyAndUseHelpers() {
    var economy = Economy(startingCoins: 30)
    #expect(economy.buy(.stabilizer) == true)
    #expect(economy.inventory[.stabilizer] == 1)
    #expect(economy.coins == 0, "stabilizer costs 30, started with 30")
    #expect(economy.use(.stabilizer) == true)
    #expect(economy.inventory[.stabilizer] == 0)
    #expect(economy.use(.windBarrier) == false, "none in inventory")
  }

  @Test func iapTiersExist() {
    #expect(Economy.CoinPack.iapTiers.count == 3)
    #expect(Economy.CoinPack.iapTiers[0].priceUSD == 0.99)
    #expect(Economy.CoinPack.iapTiers[2].coins == 700)
  }
}
