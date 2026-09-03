import Foundation

/// The four biomes, cycling per chapter (spec §5, §13).
public enum Biome: String, Codable, Sendable, CaseIterable {
  case duskwoodVale, ashenMarsh, emberDepths, starlitPeaks

  public var displayName: String {
    switch self {
    case .duskwoodVale: return "Duskwood Vale"
    case .ashenMarsh: return "Ashen Marsh"
    case .emberDepths: return "Ember Depths"
    case .starlitPeaks: return "Starlit Peaks"
    }
  }
}

/// Identifies a stage in the endless campaign: chapter 1-∞, stage 1-10 (10 = boss).
public struct StageID: Sendable, Codable, Equatable {
  public let chapter: Int
  public let stage: Int

  public init(chapter: Int, stage: Int) {
    self.chapter = chapter
    self.stage = stage
  }

  /// Compact display format, e.g. "3-7".
  public var display: String { "\(chapter)-\(stage)" }
  public var isBoss: Bool { stage == 10 }
  /// 1-based global stage index across all chapters (chapter 1 stage 1 = 1).
  public var totalIndex: Int { (chapter - 1) * 10 + stage }
}

/// Chapter/stage math: endless AFK-style campaign (spec §5).
public enum StageProgression {
  private static let hpBase = 500.0
  private static let attackBase = 40.0
  private static let defenseBase = 20.0
  private static let growthPerStage = 1.18

  /// Biome for a chapter; cycles every 4 chapters (chapter 1 = Duskwood Vale).
  public static func biome(for chapter: Int) -> Biome {
    Biome.allCases[(chapter - 1) % Biome.allCases.count]
  }

  public static func next(after stage: StageID) -> StageID {
    stage.stage >= 10
      ? StageID(chapter: stage.chapter + 1, stage: 1)
      : StageID(chapter: stage.chapter, stage: stage.stage + 1)
  }

  /// Exponential difficulty curve: base × growthPerStage^(totalIndex-1), bosses multiplied.
  public static func enemyStats(for stage: StageID) -> StatBlock {
    let stagesIn = Double(stage.totalIndex - 1)
    let growth = pow(growthPerStage, stagesIn)
    let bossMult = stage.isBoss ? 3.0 : 1.0
    return StatBlock(
      hp: hpBase * growth * bossMult,
      attack: attackBase * growth * (stage.isBoss ? 1.4 : 1.0),
      defense: defenseBase * growth * (stage.isBoss ? 1.5 : 1.0),
      speed: 1.0 + stagesIn * 0.01,
      critChance: 0,
      critDamage: 0
    )
  }

  /// 3-5 regular enemies depending on stage depth; bosses fight alone.
  public static func enemyCount(for stage: StageID) -> Int {
    stage.isBoss ? 1 : min(5, 3 + stage.stage / 4)
  }

  /// Gold per minute of idle income at this stage (flat best-stage rate, spec §8).
  public static func idleRate(for stage: StageID) -> Int {
    Int(50 * pow(1.15, Double(stage.totalIndex - 1)))
  }

  /// One-time gold reward for clearing a stage.
  public static func battleReward(for stage: StageID) -> Int {
    Int(100 * pow(1.15, Double(stage.totalIndex - 1)))
  }
}
