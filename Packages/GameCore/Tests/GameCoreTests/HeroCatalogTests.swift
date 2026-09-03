import Testing
@testable import GameCore

@Suite struct HeroCatalogTests {
  @Test func catalogHasExactly20Heroes() {
    #expect(HeroCatalog.all.count == 20)
  }

  @Test func fiveHeroesPerFaction() {
    for faction in Faction.allCases {
      #expect(HeroCatalog.faction(faction).count == 5, "faction \(faction) needs 5 heroes")
    }
  }

  @Test func rarityDistribution() {
    #expect(HeroCatalog.byRarity(.legendary).count == 4)
    #expect(HeroCatalog.byRarity(.epic).count == 6)
    #expect(HeroCatalog.byRarity(.rare).count == 6)
    #expect(HeroCatalog.byRarity(.common).count == 4)
  }

  @Test func allSevenRolesPresent() {
    let roles = Set(HeroCatalog.all.map(\.role))
    #expect(roles.count == 7)
  }

  @Test func everyHeroHasUltimateAndTwoPassives() {
    for hero in HeroCatalog.all {
      #expect(!hero.ultimate.name.isEmpty)
      #expect(hero.passives.count == 2)
    }
  }

  @Test func uniqueIDs() {
    #expect(Set(HeroCatalog.all.map(\.id)).count == 20)
  }

  @Test func legendariesHaveUniqueMechanic() {
    for hero in HeroCatalog.byRarity(.legendary) {
      #expect(hero.ultimate.effect != .damage) // unique mechanic, not plain damage
    }
  }
}
