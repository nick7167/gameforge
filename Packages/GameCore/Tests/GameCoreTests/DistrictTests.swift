import Testing
@testable import GameCore

@Suite struct DistrictTests {
  @Test func v1CatalogHasEightTypes() {
    #expect(DistrictType.v1Catalog.count == 8)
    #expect(Set(DistrictType.v1Catalog.map(\.id)).count == 8, "ids must be unique")
  }

  @Test func footprintsAreWithinBounds() {
    for t in DistrictType.v1Catalog {
      #expect((1...3).contains(t.footprint), "\(t.id) footprint out of range")
      #expect((1...5).contains(t.weight))
    }
  }

  @Test func levelForXP() {
    #expect(UnlockLadder.levelForXP(0) == 1)
    #expect(UnlockLadder.levelForXP(99) == 1)
    #expect(UnlockLadder.levelForXP(100) == 2)
    #expect(UnlockLadder.levelForXP(250) == 3)
  }

  @Test func unlockGating() {
    let all = DistrictType.v1Catalog
    let level1 = UnlockLadder.unlockedTypes(level: 1)
    #expect(level1.count < all.count, "level 1 must not unlock everything")
    #expect(UnlockLadder.unlockedTypes(level: 99).count == all.count)
    #expect(level1.allSatisfy { $0.requiredLevel <= 1 })
  }
}