import Foundation
import Testing
@testable import GameCore

@Suite struct QuestSessionTests {
  @Test func claimQuestGrantsRewards() {
    let quest = QuestSystem.dailies[0]
    var session = EmberSession(profile: .new(), rngSeed: 42, configure: {
      $0.quests.record(metric: quest.metric, amount: quest.goal)
    })
    #expect(session.claimQuest(questID: quest.id) == true)
    #expect(session.profile.wallet.balance(of: .questTokens) >= quest.rewardQuestTokens)
    #expect(session.claimQuest(questID: quest.id) == false)  // already claimed
  }

  @Test func claimQuestRejectsIncomplete() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    #expect(session.claimQuest(questID: QuestSystem.dailies[0].id) == false)
  }

  @Test func claimQuestRejectsUnknown() {
    var session = EmberSession(profile: .new(), rngSeed: 42)
    #expect(session.claimQuest(questID: "no-such-quest") == false)
  }

  @Test func claimQuestGrantsGems() {
    let quest = QuestSystem.dailies[1]  // summon: 20 gems
    var session = EmberSession(profile: .new(), rngSeed: 42, configure: {
      $0.quests.record(metric: quest.metric, amount: quest.goal)
    })
    let gemsBefore = session.profile.wallet.balance(of: .gems)
    #expect(session.claimQuest(questID: quest.id) == true)
    #expect(session.profile.wallet.balance(of: .gems) == gemsBefore + quest.rewardGems)
  }
}
