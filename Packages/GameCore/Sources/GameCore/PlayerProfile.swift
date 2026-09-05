import Foundation

/// A hero the player owns, with progression and equipped gear (spec §14).
public struct OwnedHero: Sendable, Codable, Identifiable {
  public var id: String { definitionID }
  public let definitionID: String
  public var level: Int
  public var stars: Int
  public var xp: Int
  public var gear: [GearSlot: GearItem]

  public init(definitionID: String, level: Int = 1, stars: Int = 1) {
    self.definitionID = definitionID
    self.level = level
    self.stars = stars
    self.xp = 0
    self.gear = [:]
  }

  /// Effective combat stats: catalog base, scaled by level (+6%/level above 1)
  /// and stars (+12%/star above 1), plus gear. Gear contributions are built with
  /// zeroed crit fields so StatBlock's defaults (0.05 crit / 1.5 crit damage)
  /// never leak into hero stats from equipment.
  public func stats() -> StatBlock {
    guard let def = HeroCatalog.hero(id: definitionID) else { return .zero }
    let levelMult = 1.0 + Double(level - 1) * 0.06
    let starMult = 1.0 + Double(stars - 1) * 0.12
    var stats = def.baseStats * levelMult * starMult
    for (_, item) in gear {
      stats += Self.gearStats(item)
    }
    return stats
  }

  /// Gear contributions are already zero-based crit-wise:
  /// `EquipmentSystem.stats(for:)` returns a StatBlock with zeroed crit fields,
  /// so gear only contributes what its main/sub stats actually say.
  private static func gearStats(_ item: GearItem) -> StatBlock {
    EquipmentSystem.stats(for: item)
  }

  /// Direct gear mutation for the session layer (equipping, enhancing).
  public mutating func setGear(_ item: GearItem, slot: GearSlot) {
    gear[slot] = item
  }
}

/// Everything the player owns. Persisted locally (Plan 2 adds backend sync).
public struct PlayerProfile: Sendable, Codable {
  public var name: String
  public var accountLevel: Int
  public var wallet: Wallet
  public var ownedHeroes: [OwnedHero]
  public var squad: [String]
  public var bestStage: StageID
  public var gacha: GachaState
  public var quests: QuestSystem
  public var equipment: EquipmentSystem
  public var totalBattles: Int
  public var totalSummons: Int
  /// All gear ever dropped (spec §7). Equipped copies live on `OwnedHero.gear`.
  public private(set) var gearInventory: [GearItem] = []
  /// Last idle-income claim timestamp, so offline income survives relaunch.
  public var lastIdleClaim: Date?

  public init(
    name: String, accountLevel: Int, wallet: Wallet, ownedHeroes: [OwnedHero], squad: [String],
    bestStage: StageID, gacha: GachaState, quests: QuestSystem, equipment: EquipmentSystem,
    totalBattles: Int, totalSummons: Int
  ) {
    self.name = name
    self.accountLevel = accountLevel
    self.wallet = wallet
    self.ownedHeroes = ownedHeroes
    self.squad = squad
    self.bestStage = bestStage
    self.gacha = gacha
    self.quests = quests
    self.equipment = equipment
    self.totalBattles = totalBattles
    self.totalSummons = totalSummons
  }

  /// Decoding support: profiles persisted before gear inventory / idle tracking
  /// existed decode with empty inventory and no last-claim timestamp.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    accountLevel = try container.decode(Int.self, forKey: .accountLevel)
    wallet = try container.decode(Wallet.self, forKey: .wallet)
    ownedHeroes = try container.decode([OwnedHero].self, forKey: .ownedHeroes)
    squad = try container.decode([String].self, forKey: .squad)
    bestStage = try container.decode(StageID.self, forKey: .bestStage)
    gacha = try container.decode(GachaState.self, forKey: .gacha)
    quests = try container.decode(QuestSystem.self, forKey: .quests)
    equipment = try container.decode(EquipmentSystem.self, forKey: .equipment)
    totalBattles = try container.decode(Int.self, forKey: .totalBattles)
    totalSummons = try container.decode(Int.self, forKey: .totalSummons)
    gearInventory = try container.decodeIfPresent([GearItem].self, forKey: .gearInventory) ?? []
    lastIdleClaim = try container.decodeIfPresent(Date.self, forKey: .lastIdleClaim)
  }

  /// Append gear drops to the inventory (called by the session on battle loot).
  public mutating func addToGearInventory(_ items: [GearItem]) {
    gearInventory.append(contentsOf: items)
  }

  /// Remove a gear item by ID from the inventory (called by the session when
  /// a piece of gear is equipped to a hero). Returns true if removed.
  @discardableResult
  public mutating func removeFromGearInventory(_ id: UUID) -> Bool {
    guard let index = gearInventory.firstIndex(where: { $0.id == id }) else { return false }
    gearInventory.remove(at: index)
    return true
  }

  /// Fresh profile: starter squad (one hero per faction + one extra DPS),
  /// 2000 gold, 300 gems, campaign at 1-1.
  public static func new() -> PlayerProfile {
    let starterIDs = ["torchbearer", "snowcap", "mosslings", "duskhound", "sparkmage"]
    let owned = starterIDs.map { OwnedHero(definitionID: $0) }
    return PlayerProfile(
      name: "Keeper",
      accountLevel: 1,
      wallet: Wallet(balances: [.gold: 2000, .gems: 300]),
      ownedHeroes: owned,
      squad: starterIDs,
      bestStage: StageID(chapter: 1, stage: 1),
      gacha: GachaState(),
      quests: QuestSystem(),
      equipment: EquipmentSystem(),
      totalBattles: 0,
      totalSummons: 0
    )
  }
}
