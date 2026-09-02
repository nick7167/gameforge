import Testing
@testable import GameCore

@Suite struct CollapseRulesTests {
  func makeTower(height: Int) -> TowerState {
    var tower = TowerState()
    for tick in 0..<height {
      tower.place(DistrictType.v1Catalog[tick % DistrictType.v1Catalog.count], at: GridPoint(x: 0, z: 0), tick: UInt64(tick))
    }
    return tower
  }

  @Test func collapseRemovesExactlyOneDistrict() {
    var tower = makeTower(height: 5)
    var rules = CollapseRules()
    let outcome = rules.resolveCollapse(cause: .leanOverflow, tower: &tower)
    #expect(outcome.removedDistrict != nil)
    #expect(tower.districts.count == 4)
    #expect(outcome.consecutiveCollapses == 1)
  }

  @Test func cascadeCapNeverRemovesMoreThanOne() {
    var tower = makeTower(height: 5)
    var rules = CollapseRules()
    _ = rules.resolveCollapse(cause: .gustTopple, tower: &tower)
    #expect(tower.districts.count == 4, "one collapse event = one district, never a cascade")
  }

  @Test func successfulPlacementResetsCounter() {
    var tower = makeTower(height: 3)
    var rules = CollapseRules()
    _ = rules.resolveCollapse(cause: .impact, tower: &tower)
    rules.registerPlacement()
    #expect(rules.foundationLost() == false)
  }

  @Test func threeConsecutiveCollapsesLoseFoundation() {
    var tower = makeTower(height: 6)
    var rules = CollapseRules()
    _ = rules.resolveCollapse(cause: .leanOverflow, tower: &tower)
    _ = rules.resolveCollapse(cause: .leanOverflow, tower: &tower)
    #expect(rules.foundationLost() == false)
    _ = rules.resolveCollapse(cause: .leanOverflow, tower: &tower)
    #expect(rules.foundationLost() == true)
  }

  @Test func reviveAvailableOncePerCollapse() {
    var tower = makeTower(height: 3)
    var rules = CollapseRules()
    let outcome = rules.resolveCollapse(cause: .impact, tower: &tower)
    #expect(rules.shouldOfferRevive(after: outcome))
    #expect(rules.revive() == true)
    #expect(rules.revive() == false, "no double revive without a new collapse")
    let outcome2 = rules.resolveCollapse(cause: .impact, tower: &tower)
    #expect(rules.shouldOfferRevive(after: outcome2))
  }

  @Test func emptyTowerCollapseRemovesNothing() {
    var tower = TowerState()
    var rules = CollapseRules()
    let outcome = rules.resolveCollapse(cause: .impact, tower: &tower)
    #expect(outcome.removedDistrict == nil)
    #expect(outcome.towerEmptyAfter == true)
  }

  @Test func declineReviveClearsOffer() {
    var tower = makeTower(height: 3)
    var rules = CollapseRules()
    let outcome = rules.resolveCollapse(cause: .impact, tower: &tower)
    #expect(rules.shouldOfferRevive(after: outcome))
    rules.declineRevive()
    #expect(rules.revive() == false, "declined offer must not be claimable later")
  }
}
