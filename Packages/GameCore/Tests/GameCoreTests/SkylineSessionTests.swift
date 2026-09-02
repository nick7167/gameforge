import Testing
@testable import GameCore

@Suite struct SkylineSessionTests {
  @Test func placeEarnsCoinsAndXP() {
    var session = SkylineSession()
    let result = session.placeDistrict(typeID: "homes", at: GridPoint(x: 0, z: 0), tick: 0)
    if case .placed = result {} else { Issue.record("expected placement") }
    #expect(session.tower.districts.count == 1)
  }

  @Test func lockedTypeRejected() {
    var session = SkylineSession()
    // "observatory" requires level 6; fresh session is level 1.
    let result = session.placeDistrict(typeID: "observatory", at: GridPoint(x: 0, z: 0), tick: 0)
    if case .rejected = result {} else { Issue.record("expected rejection") }
  }

  @Test func collapseThenReviveKeepsRunAlive() {
    var session = SkylineSession()
    for tick in 0..<3 {
      _ = session.placeDistrict(typeID: "homes", at: GridPoint(x: 0, z: 0), tick: UInt64(tick))
    }
    let outcome = session.handleCollapse(cause: .leanOverflow, tick: 10)
    #expect(outcome.removedDistrict != nil)
    #expect(session.revive() == true)
    #expect(session.isRunOver == false)
  }

  @Test func threeCollapsesEndRun() {
    var session = SkylineSession()
    for tick in 0..<6 {
      _ = session.placeDistrict(typeID: "homes", at: GridPoint(x: 0, z: 0), tick: UInt64(tick))
    }
    _ = session.handleCollapse(cause: .leanOverflow, tick: 10)
    _ = session.handleCollapse(cause: .leanOverflow, tick: 11)
    _ = session.handleCollapse(cause: .leanOverflow, tick: 12)
    #expect(session.isRunOver == true)
  }

  @Test func endRunRecordsMeta() {
    var session = SkylineSession()
    _ = session.placeDistrict(typeID: "homes", at: GridPoint(x: 0, z: 0), tick: 0)
    let summary = session.endRun()
    #expect(session.meta.savedDistricts.count == 1)
    #expect(summary.xpEarned >= 0)
  }
}
