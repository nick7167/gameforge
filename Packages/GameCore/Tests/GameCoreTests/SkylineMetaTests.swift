import Testing
import Foundation
@testable import GameCore

@Suite struct SkylineMetaTests {
  @Test func recordRunPersistsDistrictsAndXP() {
    var meta = SkylineMeta()
    var tower = TowerState()
    tower.place(DistrictType.v1Catalog[0], at: GridPoint(x: 0, z: 0), tick: 0)
    meta.recordRun(districts: tower.districts, xpEarned: 120)
    #expect(meta.savedDistricts.count == 1)
    #expect(meta.xp == 120)
    #expect(meta.level == 2)
  }

  @Test func unlockDerivation() {
    var meta = SkylineMeta()
    #expect(meta.unlockedTypeIDs.count == 3, "level 1 unlocks 3 types")
    meta.addXP(300)
    #expect(meta.level == 4)
    #expect(meta.unlockedTypeIDs.contains("tower"))
  }

  @Test func milestoneThresholds() {
    #expect(SkylineMeta.Milestone.milestone(for: 100) == nil)
    #expect(SkylineMeta.Milestone.milestone(for: 150) == .clouds)
    #expect(SkylineMeta.Milestone.milestone(for: 450) == .space)
    #expect(SkylineMeta.Milestone.milestone(for: 900) == .stratosphere)
  }

  @Test func dailyBonusDeterministicPerDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let day1 = Date(timeIntervalSince1970: 1_700_000_000)
    let day2 = day1.addingTimeInterval(86_400)
    #expect(SkylineMeta.dailyBonusCoins(date: day1, calendar: calendar) == 20)
    #expect(SkylineMeta.dailyBonusCoins(date: day2, calendar: calendar) == 20)
  }
}
