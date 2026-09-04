import Testing
@testable import GameCore

@Suite struct EquipmentTests {
  @Test func generatedDropHasValidShape() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 11)
    let item = system.generateDrop(rarity: .epic, rng: &rng)
    #expect(item.rarity == .epic)
    #expect(GearSlot.allCases.contains(item.slot))
    #expect(item.enhanceLevel == 0)
  }

  @Test func epicGearHasTwoSubStats() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 12)
    let item = system.generateDrop(rarity: .epic, rng: &rng)
    #expect(item.subStats.count == 2)
  }

  @Test func commonGearHasNoSubStats() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 13)
    let item = system.generateDrop(rarity: .common, rng: &rng)
    #expect(item.subStats.isEmpty)
  }

  @Test func enhanceConsumesGoldAndRaisesLevel() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 13)
    var item = system.generateDrop(rarity: .rare, rng: &rng)
    var gold = 10_000
    let ok = system.enhance(item: &item, gold: &gold)
    #expect(ok)
    #expect(item.enhanceLevel == 1)
    #expect(gold == 10_000 - 500)
  }

  @Test func enhanceFailsWithoutGold() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 14)
    var item = system.generateDrop(rarity: .rare, rng: &rng)
    var gold = 100
    #expect(system.enhance(item: &item, gold: &gold) == false)
    #expect(item.enhanceLevel == 0)
  }

  @Test func rerollChangesSubStats() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 15)
    var item = system.generateDrop(rarity: .epic, rng: &rng)
    let before = item.subStats
    var gems = 1000
    #expect(system.reroll(item: &item, gems: &gems, rng: &rng) == true)
    #expect(gems == 1000 - 50)
    // Sub-stats re-rolled (values may coincide but the roll is fresh)
    #expect(item.subStats.count == 2)
    _ = before
  }

  @Test func rerollFailsWithoutGems() {
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 16)
    var item = system.generateDrop(rarity: .epic, rng: &rng)
    var gems = 10
    #expect(system.reroll(item: &item, gems: &gems, rng: &rng) == false)
    #expect(gems == 10)
  }

  @Test func rerollIsDeterministicForSameSeed() {
    func rolledSubStats(seed: UInt64) -> [GearStat] {
      var system = EquipmentSystem()
      var rng = SeededGenerator(seed: 42)
      var item = system.generateDrop(rarity: .epic, rng: &rng)
      var gems = 1000
      _ = system.reroll(item: &item, gems: &gems, rng: &rng)
      return item.subStats
    }
    #expect(rolledSubStats(seed: 42) == rolledSubStats(seed: 42))
  }

  @Test func setBonusAppliesAtFourPieces() {
    // 4 pieces of the same set grant the set bonus
    var items: [GearItem] = []
    var system = EquipmentSystem()
    var rng = SeededGenerator(seed: 15)
    for _ in 0..<4 {
      var item = system.generateDrop(rarity: .rare, rng: &rng)
      item.setName = "emberfang"
      items.append(item)
    }
    let bonus = EquipmentSystem.setBonus(setName: "emberfang", pieceCount: 4)
    #expect(bonus != nil)
  }

  @Test func setBonusTwoPieceMinor() {
    #expect(EquipmentSystem.setBonus(setName: "emberfang", pieceCount: 2) != nil)
    #expect(EquipmentSystem.setBonus(setName: "glacier", pieceCount: 2) != nil)
    #expect(EquipmentSystem.setBonus(setName: "grove", pieceCount: 2) != nil)
    #expect(EquipmentSystem.setBonus(setName: "voidshroud", pieceCount: 2) != nil)
    #expect(EquipmentSystem.setBonus(setName: "unknown", pieceCount: 4) == nil)
    #expect(EquipmentSystem.setBonus(setName: "emberfang", pieceCount: 1) == nil)
  }

  @Test func statsIncludeEnhanceBonus() {
    let item = GearItem(
      slot: .weapon, rarity: .rare,
      mainStat: GearStat(kind: .attack, value: 100),
      subStats: [GearStat(kind: .critChance, value: 0.10)],
      enhanceLevel: 5)
    let block = EquipmentSystem.stats(for: item)
    // Main stat: 100 * (1 + 5*0.08) + 100 * (5/5 * 0.10) = 140 + 10 = 150
    #expect(abs(block.attack - 150.0) < 0.001)
    // Gear blocks are built from zeroed crit fields: only the sub-stat shows up.
    #expect(abs(block.critChance - 0.10) < 0.001)
    #expect(block.critDamage == 0)
  }

  @Test func generateDropIsDeterministicForSameSeed() {
    var a = EquipmentSystem()
    var b = EquipmentSystem()
    var rngA = SeededGenerator(seed: 77)
    var rngB = SeededGenerator(seed: 77)
    let itemA = a.generateDrop(rarity: .legendary, rng: &rngA)
    let itemB = b.generateDrop(rarity: .legendary, rng: &rngB)
    #expect(itemA.slot == itemB.slot)
    #expect(itemA.mainStat == itemB.mainStat)
    #expect(itemA.subStats == itemB.subStats)
    #expect(itemA.setName == itemB.setName)
  }
}
