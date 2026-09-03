/// Combat stats for a hero or enemy. All additive; multipliers applied by BattleEngine.
public struct StatBlock: Sendable, Codable, AdditiveArithmetic {
  public var hp: Double
  public var attack: Double
  public var defense: Double
  public var speed: Double
  public var critChance: Double
  public var critDamage: Double

  public init(
    hp: Double = 0, attack: Double = 0, defense: Double = 0, speed: Double = 0,
    critChance: Double = 0.05, critDamage: Double = 1.5
  ) {
    self.hp = hp
    self.attack = attack
    self.defense = defense
    self.speed = speed
    self.critChance = critChance
    self.critDamage = critDamage
  }

  public static var zero: StatBlock { StatBlock() }

  public static func + (lhs: StatBlock, rhs: StatBlock) -> StatBlock {
    StatBlock(
      hp: lhs.hp + rhs.hp, attack: lhs.attack + rhs.attack, defense: lhs.defense + rhs.defense,
      speed: lhs.speed + rhs.speed, critChance: lhs.critChance + rhs.critChance,
      critDamage: lhs.critDamage + rhs.critDamage)
  }

  public static func - (lhs: StatBlock, rhs: StatBlock) -> StatBlock {
    StatBlock(
      hp: lhs.hp - rhs.hp, attack: lhs.attack - rhs.attack, defense: lhs.defense - rhs.defense,
      speed: lhs.speed - rhs.speed, critChance: lhs.critChance - rhs.critChance,
      critDamage: lhs.critDamage - rhs.critDamage)
  }

  public static func * (lhs: StatBlock, rhs: Double) -> StatBlock {
    StatBlock(
      hp: lhs.hp * rhs, attack: lhs.attack * rhs, defense: lhs.defense * rhs,
      speed: lhs.speed, critChance: lhs.critChance, critDamage: lhs.critDamage)
  }
}
