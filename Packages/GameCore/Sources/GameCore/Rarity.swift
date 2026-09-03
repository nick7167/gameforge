/// Hero/gear rarity. Raw value doubles as sort order and gacha weight index.
public enum Rarity: Int, Codable, Comparable, Sendable {
  case common = 0, rare = 1, epic = 2, legendary = 3

  public static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.rawValue < rhs.rawValue }

  /// UI color language (spec §13): gray/blue/purple/gold.
  public var uiColorHex: UInt32 {
    switch self {
    case .common: 0x9E9E9E
    case .rare: 0x42A5F5
    case .epic: 0xAB47BC
    case .legendary: 0xFFD76A
    }
  }
}
