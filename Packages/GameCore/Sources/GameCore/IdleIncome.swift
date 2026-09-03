import Foundation

/// Tracks when the player last claimed offline income (spec §8).
public struct IdleIncomeState: Sendable, Codable, Equatable {
  public var lastClaimDate: Date?

  public init(lastClaimDate: Date? = nil) {
    self.lastClaimDate = lastClaimDate
  }
}

/// Offline income math (spec §8): flat best-stage rate, capped.
public enum IdleIncome {
  public static let baseCapHours = 12
  public static let monthlyCardCapHours = 24

  /// Gold earned while away. Rate comes from the player's best cleared stage.
  public static func earnings(
    bestStage: StageID, secondsAway: Double, capHours: Int = IdleIncome.baseCapHours
  ) -> (gold: Int, secondsCapped: Double) {
    let cappedSeconds = min(secondsAway, Double(capHours) * 3600)
    let perMinute = Double(StageProgression.idleRate(for: bestStage))
    let gold = Int((cappedSeconds / 60.0) * perMinute)
    return (gold, cappedSeconds)
  }

  /// Alias for `earnings` kept for interface compatibility.
  public static func offlineEarnings(
    bestStage: StageID, secondsAway: Double, capHours: Int = IdleIncome.baseCapHours
  ) -> (gold: Int, secondsCapped: Double) {
    earnings(bestStage: bestStage, secondsAway: secondsAway, capHours: capHours)
  }

  /// "Fast rewards": instantly claim N hours of idle income (2h free daily).
  public static func fastReward(bestStage: StageID, hours: Double = 2) -> Int {
    earnings(bestStage: bestStage, secondsAway: hours * 3600).gold
  }
}
