/// Hero roles (spec §4.2).
public enum HeroRole: String, Codable, Sendable, CaseIterable {
  case tank, dps, healer, support, ranger, controller, assassin
}

/// Ultimate effects. Legendaries must use a non-`.damage` effect (unique mechanic).
public enum UltimateEffect: Codable, Sendable, Equatable {
  case damage
  case healAll(percent: Double)
  case shieldAll(percent: Double)
  case stunAll(duration: Double)
  case buffAttack(percent: Double, duration: Double)
  case execute(threshold: Double)          // Void legendaries: bonus dmg below HP%
  case chainDamage(bounces: Int)           // Ember legendaries: hits multiple foes
  case freezeAll(duration: Double)         // Frost legendaries
  case lifesteal(percent: Double)          // Verdant legendaries
}

public struct UltimateDefinition: Sendable, Codable {
  public let id: String
  public let name: String
  public let damageMultiplier: Double
  public let effect: UltimateEffect

  public init(id: String, name: String, damageMultiplier: Double = 2.5, effect: UltimateEffect = .damage) {
    self.id = id
    self.name = name
    self.damageMultiplier = damageMultiplier
    self.effect = effect
  }
}

public struct PassiveDefinition: Sendable, Codable {
  public let id: String
  public let name: String
  public let description: String

  public init(id: String, name: String, description: String) {
    self.id = id
    self.name = name
    self.description = description
  }
}

public struct HeroDefinition: Sendable, Identifiable, Codable {
  public let id: String
  public let name: String
  public let faction: Faction
  public let rarity: Rarity
  public let role: HeroRole
  public let baseStats: StatBlock
  public let ultimate: UltimateDefinition
  public let passives: [PassiveDefinition]
  public let lore: String
}

/// The launch roster: 20 heroes, 5 per faction, 4L/6E/6R/4C (spec §6.1).
public enum HeroCatalog {
  public static let all: [HeroDefinition] = ember + frost + verdant + `void`

  // MARK: - Ember (burst damage)

  public static let ember: [HeroDefinition] = [
    HeroDefinition(
      id: "pyrelord", name: "Pyrelord", faction: .ember, rarity: .legendary, role: .dps,
      baseStats: StatBlock(hp: 2400, attack: 190, defense: 90, speed: 1.1, critChance: 0.20, critDamage: 2.0),
      ultimate: UltimateDefinition(id: "inferno-slash", name: "Inferno Slash", damageMultiplier: 3.2, effect: .chainDamage(bounces: 3)),
      passives: [
        PassiveDefinition(id: "pyrelord-p1", name: "Kindled Fury", description: "Crits grant +5% attack for 5s (stacks 3x)."),
        PassiveDefinition(id: "pyrelord-p2", name: "Burning Aura", description: "Nearby enemies take 10% attack as burn per second.")
      ],
      lore: "The last flame of a fallen citadel, burning with purpose."
    ),
    HeroDefinition(
      id: "cinderblade", name: "Cinderblade", faction: .ember, rarity: .epic, role: .assassin,
      baseStats: StatBlock(hp: 1500, attack: 130, defense: 60, speed: 1.3, critChance: 0.25, critDamage: 1.8),
      ultimate: UltimateDefinition(id: "ember-storm", name: "Ember Storm", damageMultiplier: 2.8, effect: .damage),
      passives: [
        PassiveDefinition(id: "cinderblade-p1", name: "Backdraft", description: "+30% damage against enemies below 40% HP."),
        PassiveDefinition(id: "cinderblade-p2", name: "Heat Haze", description: "10% chance to dodge attacks.")
      ],
      lore: "A duelist whose blade never cools."
    ),
    HeroDefinition(
      id: "ashguard", name: "Ashguard", faction: .ember, rarity: .rare, role: .tank,
      baseStats: StatBlock(hp: 1900, attack: 70, defense: 110, speed: 0.9),
      ultimate: UltimateDefinition(id: "magma-wall", name: "Magma Wall", damageMultiplier: 1.2, effect: .shieldAll(percent: 0.15)),
      passives: [
        PassiveDefinition(id: "ashguard-p1", name: "Molten Core", description: "Reflects 12% of damage taken."),
        PassiveDefinition(id: "ashguard-p2", name: "Ember Skin", description: "Takes 10% less damage from burns.")
      ],
      lore: "Forged in the pyres, sworn to stand until the last ember fades."
    ),
    HeroDefinition(
      id: "sparkmage", name: "Sparkmage", faction: .ember, rarity: .rare, role: .controller,
      baseStats: StatBlock(hp: 1200, attack: 95, defense: 45, speed: 1.0),
      ultimate: UltimateDefinition(id: "static-field", name: "Static Field", damageMultiplier: 1.8, effect: .stunAll(duration: 2.0)),
      passives: [
        PassiveDefinition(id: "sparkmage-p1", name: "Overcharge", description: "Every 3rd attack deals +50% damage."),
        PassiveDefinition(id: "sparkmage-p2", name: "Conductive", description: "Stunned enemies take +15% damage.")
      ],
      lore: "She bottled the first lightning of the Emberfall and never stopped."
    ),
    HeroDefinition(
      id: "torchbearer", name: "Torchbearer", faction: .ember, rarity: .common, role: .support,
      baseStats: StatBlock(hp: 1000, attack: 60, defense: 40, speed: 1.0),
      ultimate: UltimateDefinition(id: "rally-flame", name: "Rally Flame", damageMultiplier: 1.0, effect: .buffAttack(percent: 0.15, duration: 8.0)),
      passives: [
        PassiveDefinition(id: "torchbearer-p1", name: "Warm Light", description: "Allies regenerate 1% HP per second."),
        PassiveDefinition(id: "torchbearer-p2", name: "Cheer", description: "+5% attack to the ally with the lowest HP.")
      ],
      lore: "Where the torch passes, hope follows."
    )
  ]

  public static let frost: [HeroDefinition] = [
    HeroDefinition(
      id: "glacia", name: "Glacia", faction: .frost, rarity: .legendary, role: .controller,
      baseStats: StatBlock(hp: 2100, attack: 150, defense: 100, speed: 1.0),
      ultimate: UltimateDefinition(id: "absolute-zero", name: "Absolute Zero", damageMultiplier: 2.0, effect: .freezeAll(duration: 3.0)),
      passives: [
        PassiveDefinition(id: "glacia-p1", name: "Winter's Grasp", description: "Frozen enemies take +25% damage."),
        PassiveDefinition(id: "glacia-p2", name: "Cold Snap", description: "Every 5th attack freezes for 1s.")
      ],
      lore: "She remembers when the sun last set — and intends to see it again."
    ),
    HeroDefinition(
      id: "frostwarden", name: "Frostwarden", faction: .frost, rarity: .epic, role: .healer,
      baseStats: StatBlock(hp: 1800, attack: 90, defense: 95, speed: 1.0),
      ultimate: UltimateDefinition(id: "glacial-mend", name: "Glacial Mend", damageMultiplier: 1.0, effect: .healAll(percent: 0.20)),
      passives: [
        PassiveDefinition(id: "frostwarden-p1", name: "Rime Regrowth", description: "Healing also grants a 5% shield."),
        PassiveDefinition(id: "frostwarden-p2", name: "Chill Aura", description: "Nearby enemies attack 10% slower.")
      ],
      lore: "Her mercy is the quiet kind — the kind that lets you keep fighting."
    ),
    HeroDefinition(
      id: "sleetarcher", name: "Sleetarcher", faction: .frost, rarity: .rare, role: .ranger,
      baseStats: StatBlock(hp: 1100, attack: 95, defense: 40, speed: 1.2),
      ultimate: UltimateDefinition(id: "hail-volley", name: "Hail Volley", damageMultiplier: 2.4, effect: .damage),
      passives: [
        PassiveDefinition(id: "sleetarcher-p1", name: "Piercing Cold", description: "Attacks ignore 15% of defense."),
        PassiveDefinition(id: "sleetarcher-p2", name: "Icicle Trap", description: "10% chance to slow the target by 30% for 3s.")
      ],
      lore: "One arrow, one breath, one frozen heart."
    ),
    HeroDefinition(
      id: "rimefist", name: "Rimefist", faction: .frost, rarity: .common, role: .dps,
      baseStats: StatBlock(hp: 950, attack: 70, defense: 45, speed: 1.0),
      ultimate: UltimateDefinition(id: "frost-fist", name: "Frost Fist", damageMultiplier: 2.2, effect: .damage),
      passives: [
        PassiveDefinition(id: "rimefist-p1", name: "Bruising Blow", description: "Attacks reduce target defense by 5% (stacks 2x)."),
        PassiveDefinition(id: "rimefist-p2", name: "Toughen", description: "Gains 5 defense with each hit taken (max 50).")
      ],
      lore: "He punched an iceberg once. The iceberg apologized."
    ),
    HeroDefinition(
      id: "snowcap", name: "Snowcap", faction: .frost, rarity: .common, role: .support,
      baseStats: StatBlock(hp: 1050, attack: 55, defense: 50, speed: 1.0),
      ultimate: UltimateDefinition(id: "blizzard-veil", name: "Blizzard Veil", damageMultiplier: 0.8, effect: .shieldAll(percent: 0.12)),
      passives: [
        PassiveDefinition(id: "snowcap-p1", name: "Insulating", description: "Allies take 5% less damage."),
        PassiveDefinition(id: "snowcap-p2", name: "Frostbite", description: "Attackers are slowed 8% for 2s.")
      ],
      lore: "Small, round, and unexpectedly hard to kill."
    )
  ]

  public static let verdant: [HeroDefinition] = [
    HeroDefinition(
      id: "thornbow", name: "Thornbow", faction: .verdant, rarity: .legendary, role: .ranger,
      baseStats: StatBlock(hp: 2000, attack: 185, defense: 85, speed: 1.2, critChance: 0.22, critDamage: 1.9),
      ultimate: UltimateDefinition(id: "wild-volley", name: "Wild Volley", damageMultiplier: 2.6, effect: .lifesteal(percent: 0.4)),
      passives: [
        PassiveDefinition(id: "thornbow-p1", name: "Bramble Rounds", description: "Attacks poison for 8% attack over 3s."),
        PassiveDefinition(id: "thornbow-p2", name: "Rooted", description: "+20% attack while below 50% HP.")
      ],
      lore: "The forest keeps score, and she is its ledger."
    ),
    HeroDefinition(
      id: "grovekeeper", name: "Grovekeeper", faction: .verdant, rarity: .epic, role: .healer,
      baseStats: StatBlock(hp: 1900, attack: 85, defense: 95, speed: 1.0),
      ultimate: UltimateDefinition(id: "life-bloom", name: "Life Bloom", damageMultiplier: 0.9, effect: .healAll(percent: 0.20)),
      passives: [
        PassiveDefinition(id: "grovekeeper-p1", name: "Deep Roots", description: "Healing over 15% also cleanses one debuff."),
        PassiveDefinition(id: "grovekeeper-p2", name: "Photosynthesis", description: "Regenerates 2% HP per second while shielded.")
      ],
      lore: "Every wound is just a season waiting to turn."
    ),
    HeroDefinition(
      id: "barkskin", name: "Barkskin", faction: .verdant, rarity: .rare, role: .tank,
      baseStats: StatBlock(hp: 2000, attack: 65, defense: 105, speed: 0.9),
      ultimate: UltimateDefinition(id: "ironwood-aegis", name: "Ironwood Aegis", damageMultiplier: 1.0, effect: .shieldAll(percent: 0.18)),
      passives: [
        PassiveDefinition(id: "barkskin-p1", name: "Thorned Hide", description: "Attackers take 10% of damage dealt back."),
        PassiveDefinition(id: "barkskin-p2", name: "Ancient Growth", description: "Max HP increases 3% each minute of battle.")
      ],
      lore: "Older than the paths, patient as the soil."
    ),
    HeroDefinition(
      id: "petalblade", name: "Petalblade", faction: .verdant, rarity: .rare, role: .assassin,
      baseStats: StatBlock(hp: 1000, attack: 100, defense: 40, speed: 1.35, critChance: 0.28),
      ultimate: UltimateDefinition(id: "bloom-dance", name: "Petal Dance", damageMultiplier: 2.6, effect: .damage),
      passives: [
        PassiveDefinition(id: "petalblade-p1", name: "First Bloom", description: "Opening attack always crits."),
        PassiveDefinition(id: "petalblade-p2", name: "Petal Storm", description: "Kills grant +20% speed for 4s.")
      ],
      lore: "Beauty, briefly. Then the cut."
    ),
    HeroDefinition(
      id: "mosslings", name: "Mosslings", faction: .verdant, rarity: .common, role: .support,
      baseStats: StatBlock(hp: 1100, attack: 55, defense: 55, speed: 1.0),
      ultimate: UltimateDefinition(id: "spore-cloud", name: "Spore Cloud", damageMultiplier: 1.0, effect: .stunAll(duration: 1.5)),
      passives: [
        PassiveDefinition(id: "mosslings-p1", name: "Symbiosis", description: "Heals the nearest ally 1.5% HP per second."),
        PassiveDefinition(id: "mosslings-p2", name: "Hardy", description: "Immune to poison.")
      ],
      lore: "A hundred small helpers pretending to be one hero."
    )
  ]

  public static let `void`: [HeroDefinition] = [
    HeroDefinition(
      id: "nullreaper", name: "Nullreaper", faction: .void, rarity: .legendary, role: .assassin,
      baseStats: StatBlock(hp: 1900, attack: 200, defense: 80, speed: 1.3, critChance: 0.30, critDamage: 2.2),
      ultimate: UltimateDefinition(id: "void-cleave", name: "Void Cleave", damageMultiplier: 3.0, effect: .execute(threshold: 0.25)),
      passives: [
        PassiveDefinition(id: "nullreaper-p1", name: "Entropy", description: "Each hit adds +2% crit chance (max +20%)."),
        PassiveDefinition(id: "nullreaper-p2", name: "Phase Step", description: "First attack each wave cannot miss.")
      ],
      lore: "Where it passes, the world forgets to have existed."
    ),
    HeroDefinition(
      id: "duskcaller", name: "Duskcaller", faction: .void, rarity: .epic, role: .controller,
      baseStats: StatBlock(hp: 1500, attack: 110, defense: 70, speed: 1.1),
      ultimate: UltimateDefinition(id: "eclipse-brand", name: "Eclipse Brand", damageMultiplier: 2.0, effect: .stunAll(duration: 2.5)),
      passives: [
        PassiveDefinition(id: "duskcaller-p1", name: "Dread", description: "Enemies below 50% HP deal 10% less damage."),
        PassiveDefinition(id: "duskcaller-p2", name: "Umbral Siphon", description: "Heals 5% of damage dealt.")
      ],
      lore: "The dusk is not an ending. It is an appetite."
    ),
    HeroDefinition(
      id: "voidpriest", name: "Voidpriest", faction: .void, rarity: .epic, role: .support,
      baseStats: StatBlock(hp: 1600, attack: 95, defense: 80, speed: 1.0),
      ultimate: UltimateDefinition(
        id: "dark-communion", name: "Dark Communion", damageMultiplier: 1.2, effect: .buffAttack(percent: 0.25, duration: 10.0)
      ),
      passives: [
        PassiveDefinition(id: "voidpriest-p1", name: "Blood Pact", description: "Ults cost 5% HP but charge 20% faster."),
        PassiveDefinition(id: "voidpriest-p2", name: "Ominous Presence", description: "Enemies start battle with -10% attack.")
      ],
      lore: "She speaks softly, and the dark leans in to listen."
    ),
    HeroDefinition(
      id: "gloomfang", name: "Gloomfang", faction: .void, rarity: .rare, role: .dps,
      baseStats: StatBlock(hp: 1150, attack: 105, defense: 50, speed: 1.15, critChance: 0.20),
      ultimate: UltimateDefinition(id: "shadow-frenzy", name: "Shadow Frenzy", damageMultiplier: 2.5, effect: .damage),
      passives: [
        PassiveDefinition(id: "gloomfang-p1", name: "Feeding Frenzy", description: "Kills restore 10% HP."),
        PassiveDefinition(id: "gloomfang-p2", name: "Night Vision", description: "+15% crit chance against slowed enemies.")
      ],
      lore: "It was a wolf once. The dark kept the shape and lost the mercy."
    ),
    HeroDefinition(
      id: "duskhound", name: "Duskhound", faction: .void, rarity: .epic, role: .dps,
      baseStats: StatBlock(hp: 900, attack: 75, defense: 40, speed: 1.2),
      ultimate: UltimateDefinition(id: "night-rush", name: "Night Rush", damageMultiplier: 2.0, effect: .damage),
      passives: [
        PassiveDefinition(id: "duskhound-p1", name: "Relentless", description: "+10% attack for every enemy defeated (max 3)."),
        PassiveDefinition(id: "duskhound-p2", name: "Loyal", description: "Gains a 5% shield when an ally dies.")
      ],
      lore: "Good dog. Terrible omen."
    )
  ]

  public static func hero(id: String) -> HeroDefinition? {
    all.first { $0.id == id }
  }

  public static func faction(_ faction: Faction) -> [HeroDefinition] {
    all.filter { $0.faction == faction }
  }

  /// Alias for `faction(_:)`.
  public static func heroes(faction: Faction) -> [HeroDefinition] {
    HeroCatalog.faction(faction)
  }

  public static func byRarity(_ rarity: Rarity) -> [HeroDefinition] {
    all.filter { $0.rarity == rarity }
  }
}
