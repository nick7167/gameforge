/// The four hero factions. Synergy-only: no elemental counters (spec §4.2).
public enum Faction: String, CaseIterable, Codable, Sendable {
  case ember, frost, verdant, void

  /// Squad synergy bonus: 2 same-faction = +8% ATK, 4 = +20% ATK (spec §4.2).
  public var synergyAttackMultiplier: Double {
    switch self {
    case .ember, .frost, .verdant, .void: 1.0 // per-pair bonus applied by BattleEngine
    }
  }
}
