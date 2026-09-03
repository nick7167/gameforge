import Foundation

public enum QuestKind: String, Codable, Sendable {
  case daily, weekly, achievement
}

public enum QuestMetric: String, Codable, Sendable {
  case battlesWon, summons, enhances, idleClaims, goldSpent, stagesCleared
}

public struct QuestDefinition: Sendable, Identifiable, Codable, Equatable {
  public let id: String
  public let kind: QuestKind
  public let metric: QuestMetric
  public let goal: Int
  public let rewardGems: Int
  public let rewardQuestTokens: Int

  public init(id: String, kind: QuestKind, metric: QuestMetric, goal: Int, rewardGems: Int, rewardQuestTokens: Int) {
    self.id = id
    self.kind = kind
    self.metric = metric
    self.goal = goal
    self.rewardGems = rewardGems
    self.rewardQuestTokens = rewardQuestTokens
  }

  public var title: String {
    switch metric {
    case .battlesWon: return "Win \(goal) battles"
    case .summons: return "Summon \(goal)×"
    case .enhances: return "Enhance gear \(goal)×"
    case .idleClaims: return "Claim idle chest \(goal)×"
    case .goldSpent: return "Spend \(goal) gold"
    case .stagesCleared: return "Clear \(goal) stages"
    }
  }
}

public struct QuestProgress: Sendable, Codable {
  public var questID: String
  public var count: Int = 0
  public var claimed: Bool = false

  public init(questID: String, count: Int = 0, claimed: Bool = false) {
    self.questID = questID
    self.count = count
    self.claimed = claimed
  }
}

/// Quests & achievements (spec §9). Dailies, weeklies and achievements all
/// track the same metrics; reset semantics live in the app layer (Plan 2).
public struct QuestSystem: Sendable {
  public static let dailies: [QuestDefinition] = [
    QuestDefinition(id: "d-battles", kind: .daily, metric: .battlesWon, goal: 5, rewardGems: 20, rewardQuestTokens: 10),
    QuestDefinition(id: "d-summon", kind: .daily, metric: .summons, goal: 1, rewardGems: 20, rewardQuestTokens: 10),
    QuestDefinition(id: "d-enhance", kind: .daily, metric: .enhances, goal: 2, rewardGems: 15, rewardQuestTokens: 10),
    QuestDefinition(id: "d-idle", kind: .daily, metric: .idleClaims, goal: 1, rewardGems: 10, rewardQuestTokens: 5),
    QuestDefinition(id: "d-gold", kind: .daily, metric: .goldSpent, goal: 5000, rewardGems: 15, rewardQuestTokens: 10)
  ]

  public static let weeklies: [QuestDefinition] = [
    QuestDefinition(
      id: "w-battles", kind: .weekly, metric: .battlesWon,
      goal: 40, rewardGems: 100, rewardQuestTokens: 0),
    QuestDefinition(
      id: "w-stages", kind: .weekly, metric: .stagesCleared,
      goal: 30, rewardGems: 120, rewardQuestTokens: 0),
    QuestDefinition(
      id: "w-summons", kind: .weekly, metric: .summons,
      goal: 10, rewardGems: 80, rewardQuestTokens: 0)
  ]

  public static let achievements: [QuestDefinition] = [
    QuestDefinition(
      id: "a-battles-100", kind: .achievement, metric: .battlesWon,
      goal: 100, rewardGems: 200, rewardQuestTokens: 0),
    QuestDefinition(
      id: "a-battles-1000", kind: .achievement, metric: .battlesWon,
      goal: 1000, rewardGems: 1000, rewardQuestTokens: 0),
    QuestDefinition(
      id: "a-stages-50", kind: .achievement, metric: .stagesCleared,
      goal: 50, rewardGems: 250, rewardQuestTokens: 0),
    QuestDefinition(
      id: "a-stages-200", kind: .achievement, metric: .stagesCleared,
      goal: 200, rewardGems: 600, rewardQuestTokens: 0),
    QuestDefinition(
      id: "a-summons-50", kind: .achievement, metric: .summons,
      goal: 50, rewardGems: 300, rewardQuestTokens: 0),
    QuestDefinition(
      id: "a-enhances-100", kind: .achievement, metric: .enhances,
      goal: 100, rewardGems: 250, rewardQuestTokens: 0),
    QuestDefinition(
      id: "a-idle-30", kind: .achievement, metric: .idleClaims,
      goal: 30, rewardGems: 200, rewardQuestTokens: 0),
    QuestDefinition(
      id: "a-gold-1m", kind: .achievement, metric: .goldSpent,
      goal: 1_000_000, rewardGems: 500, rewardQuestTokens: 0)
  ]

  public private(set) var progress: [String: QuestProgress] = [:]

  public init() {}

  /// Updates every quest (daily, weekly, achievement) matching the metric.
  /// Already-claimed quests keep counting; the claimed flag prevents double claims.
  public mutating func record(metric: QuestMetric, amount: Int) {
    for quest in Self.dailies + Self.weeklies + Self.achievements where quest.metric == metric {
      var entry = progress[quest.id] ?? QuestProgress(questID: quest.id)
      entry.count += amount
      progress[quest.id] = entry
    }
  }

  public func progress(for questID: String) -> QuestProgress? { progress[questID] }

  @discardableResult
  public mutating func claim(questID: String, wallet: inout Wallet) -> Bool {
    let quest = Self.dailies.first { $0.id == questID }
      ?? Self.weeklies.first { $0.id == questID }
      ?? Self.achievements.first { $0.id == questID }
    guard let quest, let entry = progress[questID], !entry.claimed, entry.count >= quest.goal else { return false }
    progress[questID]?.claimed = true
    if quest.rewardGems > 0 { wallet.add(.gems, quest.rewardGems) }
    if quest.rewardQuestTokens > 0 { wallet.add(.questTokens, quest.rewardQuestTokens) }
    return true
  }
}
