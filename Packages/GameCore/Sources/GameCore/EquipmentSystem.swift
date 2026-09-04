import Foundation

public enum GearSlot: String, Codable, Sendable, CaseIterable {
  case weapon, armor, trinket, relic
}

public enum StatKind: String, Codable, Sendable, CaseIterable {
  case hp, attack, defense, speed, critChance, critDamage
}

public struct GearStat: Sendable, Codable, Equatable {
  public let kind: StatKind
  public let value: Double

  public init(kind: StatKind, value: Double) {
    self.kind = kind
    self.value = value
  }
}

public struct GearItem: Sendable, Identifiable, Codable {
  public let id: UUID
  public let slot: GearSlot
  public let rarity: Rarity
  public var mainStat: GearStat
  public var subStats: [GearStat]
  public var enhanceLevel: Int
  public var setName: String?

  public init(
    id: UUID = UUID(), slot: GearSlot, rarity: Rarity,
    mainStat: GearStat, subStats: [GearStat] = [], enhanceLevel: Int = 0, setName: String? = nil
  ) {
    self.id = id
    self.slot = slot
    self.rarity = rarity
    self.mainStat = mainStat
    self.subStats = subStats
    self.enhanceLevel = enhanceLevel
    self.setName = setName
  }
}

/// Gear generation and progression (spec §7). Enhancing never destroys gear.
public struct EquipmentSystem: Sendable, Codable {
  public static let rerollGemCost = 50

  public init() {}

  /// Roll a fresh gear drop. All randomness flows through the passed rng so
  /// drops stay reproducible from a seed.
  public mutating func generateDrop(rarity: Rarity, rng: inout SeededGenerator) -> GearItem {
    let slot = GearSlot.allCases.randomElement(using: &rng)!
    let mainStat = GearStat(
      kind: Self.mainStatKind(for: slot),
      value: Self.randomStatValue(kind: Self.mainStatKind(for: slot), rarity: rarity, rng: &rng))
    let subCount = rarity.rawValue // common 0, rare 1, epic 2, legendary 3
    var subStats: [GearStat] = []
    for _ in 0..<subCount {
      subStats.append(Self.randomSubStat(rarity: rarity, rng: &rng))
    }
    let setNames = ["emberfang", "glacier", "grove", "voidshroud"]
    let hasSet = rarity >= .epic && Double.random(in: 0..<1, using: &rng) < 0.5
    return GearItem(
      slot: slot, rarity: rarity, mainStat: mainStat, subStats: subStats,
      setName: hasSet ? setNames.randomElement(using: &rng) : nil)
  }

  /// Total stat contribution of a gear item (main + sub + enhance bonus).
  /// Crit fields are zero-based here: gear only contributes what its stats say.
  public static func stats(for item: GearItem) -> StatBlock {
    var block = StatBlock(hp: 0, attack: 0, defense: 0, speed: 0, critChance: 0, critDamage: 0)
    applyStat(item.mainStat, to: &block, multiplier: 1.0 + Double(item.enhanceLevel) * 0.08)
    for sub in item.subStats {
      applyStat(sub, to: &block, multiplier: 1.0)
    }
    // Every 5 enhance levels: +10% main stat bonus
    if item.enhanceLevel >= 5 {
      applyStat(item.mainStat, to: &block, multiplier: Double(item.enhanceLevel / 5) * 0.10)
    }
    return block
  }

  /// Set bonuses (spec §7): 2-piece minor, 4-piece major. Built from `.zero` so
  /// StatBlock's non-zero defaults (crit) never leak into a set bonus.
  public static func setBonus(setName: String, pieceCount: Int) -> StatBlock? {
    guard pieceCount >= 2 else { return nil }
    var bonus = StatBlock.zero
    switch setName {
    case "emberfang":
      if pieceCount >= 4 { bonus.critDamage = 0.25 } else { bonus.critChance = 0.05 }
    case "glacier":
      if pieceCount >= 4 { bonus.defense = 40 } else { bonus.hp = 300 }
    case "grove":
      if pieceCount >= 4 { bonus.speed = 0.15 } else { bonus.defense = 25 }
    case "voidshroud":
      if pieceCount >= 4 { bonus.critDamage = 0.35 } else { bonus.attack = 20 }
    default:
      return nil
    }
    return bonus
  }

  @discardableResult
  public mutating func enhance(item: inout GearItem, gold: inout Int) -> Bool {
    let cost = Self.enhanceCost(level: item.enhanceLevel)
    guard gold >= cost else { return false }
    gold -= cost
    item.enhanceLevel += 1
    return true
  }

  public static func enhanceCost(level: Int) -> Int { 500 * (level + 1) }

  /// Reroll sub-stats only (main stat and set are untouched). Uses the passed
  /// rng so rerolls are reproducible from a seed.
  @discardableResult
  public mutating func reroll(item: inout GearItem, gems: inout Int, rng: inout SeededGenerator) -> Bool {
    guard gems >= Self.rerollGemCost, item.rarity >= .rare else { return false }
    gems -= Self.rerollGemCost
    item.subStats = (0..<item.rarity.rawValue).map { _ in Self.randomSubStat(rarity: item.rarity, rng: &rng) }
    return true
  }

  // MARK: - Private

  private static func mainStatKind(for slot: GearSlot) -> StatKind {
    switch slot {
    case .weapon: return .attack
    case .armor: return .hp
    case .trinket: return .defense
    case .relic: return .critChance
    }
  }

  private static func randomStatValue(kind: StatKind, rarity: Rarity, rng: inout SeededGenerator) -> Double {
    let base: Double
    switch kind {
    case .hp: base = 200
    case .attack: base = 15
    case .defense: base = 10
    case .speed: base = 0.02
    case .critChance: base = 0.02
    case .critDamage: base = 0.05
    }
    let rarityMult = [1.0, 1.5, 2.2, 3.2][rarity.rawValue]
    return base * rarityMult * (0.8 + Double.random(in: 0..<1, using: &rng) * 0.4)
  }

  private static func randomSubStat(rarity: Rarity, rng: inout SeededGenerator) -> GearStat {
    let kind = StatKind.allCases.randomElement(using: &rng)!
    return GearStat(kind: kind, value: randomStatValue(kind: kind, rarity: rarity, rng: &rng) * 0.4)
  }

  private static func applyStat(_ stat: GearStat, to block: inout StatBlock, multiplier: Double) {
    let amount = stat.value * multiplier
    switch stat.kind {
    case .hp: block.hp += amount
    case .attack: block.attack += amount
    case .defense: block.defense += amount
    case .speed: block.speed += amount
    case .critChance: block.critChance += amount
    case .critDamage: block.critDamage += amount
    }
  }
}
