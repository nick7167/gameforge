import Foundation

/// Persistent meta-layer: the saved skyline, XP/level, unlocks, milestones.
public struct SkylineMeta: Codable, Sendable {
  public enum Milestone: String, Codable, Sendable, CaseIterable {
    case clouds, space, stratosphere

    public var heightThreshold: Int {
      switch self {
      case .clouds: 150
      case .space: 400
      case .stratosphere: 700
      }
    }

    /// The highest milestone reached at the given height, if any.
    public static func milestone(for height: Int) -> Milestone? {
      allCases.last { height >= $0.heightThreshold }
    }
  }

  public var savedDistricts: [District] = []
  public var xp: Int = 0

  public init() {}

  public var level: Int { UnlockLadder.levelForXP(xp) }

  public var unlockedTypeIDs: Set<String> {
    Set(UnlockLadder.unlockedTypes(level: level).map(\.id))
  }

  public mutating func addXP(_ amount: Int) {
    xp += max(0, amount)
  }

  public mutating func recordRun(districts: [District], xpEarned: Int) {
    savedDistricts = districts
    addXP(xpEarned)
  }

  /// First-run-of-the-day bonus. The caller tracks the last bonus date;
  /// this returns the flat amount so it stays deterministic per calendar day.
  public static func dailyBonusCoins(date: Date, calendar: Calendar = .current) -> Int {
    var hasher = Hasher()
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    hasher.combine(components.year)
    hasher.combine(components.month)
    hasher.combine(components.day)
    _ = hasher.finalize()
    return 20
  }
}
