import Foundation
import Testing
@testable import GameCore

@Suite struct QuestTests {
  @Test func fiveDailies() {
    #expect(QuestSystem.dailies.count == 5)
  }

  @Test func threeWeeklies() {
    #expect(QuestSystem.weeklies.count == 3)
  }

  @Test func recordingProgress() {
    var quests = QuestSystem()
    quests.record(metric: .battlesWon, amount: 3)
    let quest = QuestSystem.dailies.first { $0.metric == .battlesWon }!
    let progress = quests.progress(for: quest.id)
    #expect(progress?.count == 3)
  }

  @Test func recordUpdatesAllMatchingQuests() {
    var quests = QuestSystem()
    quests.record(metric: .battlesWon, amount: 10)
    #expect(quests.progress(for: "d-battles")?.count == 10)
    #expect(quests.progress(for: "w-battles")?.count == 10)
    #expect(quests.progress(for: "a-battles-100")?.count == 10)
    #expect(quests.progress(for: "d-summon") == nil)
  }

  @Test func claimGrantsRewardsOnce() {
    var quests = QuestSystem()
    var wallet = Wallet()
    let quest = QuestSystem.dailies[0]
    quests.record(metric: quest.metric, amount: quest.goal)
    #expect(quests.claim(questID: quest.id, wallet: &wallet) == true)
    #expect(quests.claim(questID: quest.id, wallet: &wallet) == false) // already claimed
    #expect(wallet.balance(of: .questTokens) > 0)
    #expect(wallet.balance(of: .gems) == quest.rewardGems)
  }

  @Test func claimFailsWhenIncomplete() {
    var quests = QuestSystem()
    var wallet = Wallet()
    let quest = QuestSystem.dailies[0]
    #expect(quests.claim(questID: quest.id, wallet: &wallet) == false)
  }

  @Test func claimFailsForUnknownQuest() {
    var quests = QuestSystem()
    var wallet = Wallet()
    #expect(quests.claim(questID: "nope", wallet: &wallet) == false)
  }

  @Test func achievementsExist() {
    #expect(QuestSystem.achievements.count >= 8)
  }

  @Test func questDefinitionsAreCodable() throws {
    let data = try JSONEncoder().encode(QuestSystem.dailies)
    let decoded = try JSONDecoder().decode([QuestDefinition].self, from: data)
    #expect(decoded == QuestSystem.dailies)
  }
}
