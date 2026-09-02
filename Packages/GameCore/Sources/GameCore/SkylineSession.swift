import Foundation

/// The game facade. The app layer drives this and renders its state;
/// all rules live here or in the types above.
public struct SkylineSession: Sendable {
  public private(set) var tower: TowerState
  public private(set) var collapse = CollapseRules()
  public private(set) var meta: SkylineMeta
  public private(set) var economy: Economy
  public private(set) var perfectStreak = 0
  public private(set) var placements = 0

  public init(meta: SkylineMeta = SkylineMeta(), startingCoins: Int = 0) {
    self.meta = meta
    self.tower = TowerState()
    self.economy = Economy(startingCoins: startingCoins)
  }

  public var isRunOver: Bool { collapse.foundationLost() }

  public mutating func placeDistrict(typeID: String, at origin: GridPoint, tick: UInt64) -> TowerState.PlaceResult {
    guard let type = DistrictType.v1Catalog.first(where: { $0.id == typeID }) else {
      return .rejected(reason: "unknown type")
    }
    guard meta.unlockedTypeIDs.contains(typeID) else {
      return .rejected(reason: "locked")
    }
    let result = tower.place(type, at: origin, tick: tick)
    if case .placed(let perfect) = result {
      placements += 1
      collapse.registerPlacement()
      perfectStreak = perfect ? perfectStreak + 1 : 0
      _ = economy.earnRent(districtsHoused: tower.districts.count, perfectStreak: perfectStreak)
      meta.addXP(perfect ? 10 : 5)
    }
    return result
  }

  public mutating func handleCollapse(cause: CollapseCause, tick: UInt64) -> CollapseOutcome {
    perfectStreak = 0
    return collapse.resolveCollapse(cause: cause, tower: &tower)
  }

  /// Consume an Extra Revive helper if owned; otherwise mark the ad-revive
  /// as claimable. The caller shows the rewarded ad, then calls
  /// `confirmAdRevive()` when the ad completes, or `abandonRevive()` if the
  /// player declines or the ad fails to load.
  public mutating func revive() -> Bool {
    if economy.use(.extraRevive) { return true }
    return collapse.revive()
  }

  public mutating func confirmAdRevive() {
    _ = collapse.revive()
  }

  public mutating func abandonRevive() {
    collapse.declineRevive()
  }

  public struct RunSummary: Sendable {
    public let height: Int
    public let coinsEarned: Int
    public let xpEarned: Int
    public let milestone: SkylineMeta.Milestone?
  }

  public mutating func endRun() -> RunSummary {
    let height = tower.districts.count * 10
    let milestone = SkylineMeta.Milestone.milestone(for: height)
    let xpEarned = placements * 5
    meta.recordRun(districts: tower.districts, xpEarned: xpEarned)
    return RunSummary(height: height, coinsEarned: economy.coins, xpEarned: xpEarned, milestone: milestone)
  }
}