import Foundation
import Testing
@testable import GameCore

@Suite struct StageProgressionTests {
  @Test func displayFormat() {
    let stage = StageID(chapter: 3, stage: 7)
    #expect(stage.display == "3-7")
  }

  @Test func bossOnTenthStage() {
    #expect(StageID(chapter: 2, stage: 10).isBoss)
    #expect(!StageID(chapter: 2, stage: 9).isBoss)
  }

  @Test func difficultyGrowsMonotonically() {
    let early = StageProgression.enemyStats(for: StageID(chapter: 1, stage: 1))
    let late = StageProgression.enemyStats(for: StageID(chapter: 5, stage: 5))
    #expect(late.attack > early.attack)
    #expect(late.hp > early.hp)
  }

  @Test func biomesCycle() {
    #expect(StageProgression.biome(for: 1) == .duskwoodVale)
    #expect(StageProgression.biome(for: 2) == .ashenMarsh)
    #expect(StageProgression.biome(for: 5) == .duskwoodVale) // cycles every 4
  }

  @Test func idleRateGrows() {
    #expect(StageProgression.idleRate(for: StageID(chapter: 4, stage: 1))
      > StageProgression.idleRate(for: StageID(chapter: 1, stage: 1)))
  }

  @Test func nextStageAdvances() {
    let stage = StageID(chapter: 1, stage: 9)
    #expect(StageProgression.next(after: stage) == StageID(chapter: 1, stage: 10))
    let boss = StageID(chapter: 1, stage: 10)
    #expect(StageProgression.next(after: boss) == StageID(chapter: 2, stage: 1))
  }

  @Test func enemyCountBounds() {
    #expect(StageProgression.enemyCount(for: StageID(chapter: 1, stage: 1)) == 3)
    #expect(StageProgression.enemyCount(for: StageID(chapter: 1, stage: 5)) == 4)
    #expect(StageProgression.enemyCount(for: StageID(chapter: 3, stage: 9)) == 5)
    #expect(StageProgression.enemyCount(for: StageID(chapter: 3, stage: 10)) == 1)
  }

  @Test func bossStatsStrongerThanRegular() {
    let boss = StageProgression.enemyStats(for: StageID(chapter: 2, stage: 10))
    let regular = StageProgression.enemyStats(for: StageID(chapter: 2, stage: 9))
    #expect(boss.hp > regular.hp)
    #expect(boss.attack > regular.attack)
  }

  @Test func stageIDIsCodableRoundtrip() throws {
    let original = StageID(chapter: 7, stage: 3)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(StageID.self, from: data)
    #expect(decoded == original)
  }
}
