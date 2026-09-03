import Testing
@testable import GameCore

@Suite struct IdleIncomeTests {
  @Test func earningsScaleWithTimeAndStage() {
    let short = IdleIncome.earnings(bestStage: StageID(chapter: 1, stage: 1), secondsAway: 3600)
    let long = IdleIncome.earnings(bestStage: StageID(chapter: 1, stage: 1), secondsAway: 7200)
    #expect(short.gold > 0)
    #expect(long.gold > short.gold)
  }

  @Test func twelveHourCap() {
    let day = IdleIncome.earnings(bestStage: StageID(chapter: 2, stage: 3), secondsAway: 86_400)
    let cap = IdleIncome.earnings(bestStage: StageID(chapter: 2, stage: 3), secondsAway: 12 * 3600)
    #expect(day.gold == cap.gold) // capped at 12h
  }

  @Test func monthlyCardDoublesCap() {
    let day = IdleIncome.earnings(bestStage: StageID(chapter: 2, stage: 3), secondsAway: 24 * 3600, capHours: 24)
    let base = IdleIncome.earnings(bestStage: StageID(chapter: 2, stage: 3), secondsAway: 24 * 3600)
    #expect(day.gold > base.gold)
  }

  @Test func fastRewardEqualsTwoHours() {
    let fast = IdleIncome.fastReward(bestStage: StageID(chapter: 3, stage: 1))
    let manual = IdleIncome.earnings(bestStage: StageID(chapter: 3, stage: 1), secondsAway: 2 * 3600)
    #expect(fast == manual.gold)
  }

  @Test func higherStagePaysMore() {
    #expect(IdleIncome.earnings(bestStage: StageID(chapter: 5, stage: 1), secondsAway: 3600).gold
      > IdleIncome.earnings(bestStage: StageID(chapter: 1, stage: 1), secondsAway: 3600).gold)
  }
}
