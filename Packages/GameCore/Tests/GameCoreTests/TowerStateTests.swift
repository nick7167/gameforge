import Testing
@testable import GameCore

@Suite struct TowerStateTests {
  let homes = DistrictType.v1Catalog.first { $0.id == "homes" }!

  @Test func emptyTowerAcceptsAnything() {
    var tower = TowerState()
    let result = tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 0)
    guard case .placed = result else { Issue.record("expected placed, got \(result)"); return }
    #expect(tower.districts.count == 1)
  }

  @Test func perfectPlacementDetected() {
    var tower = TowerState()
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 0)
    let result = tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 1)
    if case .placed(let perfect) = result {
      #expect(perfect)
    } else {
      Issue.record("expected placed")
    }
  }

  @Test func offCenterRaisesLean() {
    var tower = TowerState()
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 0)
    // Offset (1,0): legal (one cell of overlap) but imperfect → adds lean.
    tower.place(homes, at: GridPoint(x: 1, z: 0), tick: 1)
    #expect(tower.lean > 0)
    #expect(tower.stabilityScore() < 1.0)
  }

  @Test func rejectionWhenUnsupported() {
    var tower = TowerState()
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 0)
    let result = tower.place(homes, at: GridPoint(x: 3, z: 3), tick: 1)
    if case .rejected = result {} else { Issue.record("expected rejection") }
    #expect(tower.districts.count == 1)
  }

  @Test func curingStopsLeanContribution() {
    var tower = TowerState()
    tower.place(homes, at: GridPoint(x: 1, z: 0), tick: 0)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 1)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 2)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 3)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 4)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 5)
    tower.cure(tick: 6)
    #expect(tower.curedDistrictIDs.count > 0, "old districts should be cured")
  }

  @Test func removeTopReturnsLastPlaced() {
    var tower = TowerState()
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 0)
    tower.place(homes, at: GridPoint(x: 0, z: 0), tick: 1)
    let removed = tower.removeTop()
    #expect(removed?.placedAtTick == 1)
    #expect(tower.districts.count == 1)
  }
}
