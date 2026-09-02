import Foundation

public enum CollapseCause: String, Codable, Sendable {
  case leanOverflow, gustTopple, impact
}

public struct CollapseOutcome: Equatable, Sendable {
  public let removedDistrict: District?
  public let towerEmptyAfter: Bool
  public let consecutiveCollapses: Int

  init(removedDistrict: District?, towerEmptyAfter: Bool, consecutiveCollapses: Int) {
    self.removedDistrict = removedDistrict
    self.towerEmptyAfter = towerEmptyAfter
    self.consecutiveCollapses = consecutiveCollapses
  }
}

/// Collapse resolution: cascade cap (one district per event), revive offer
/// state, and foundation-loss tracking.
public struct CollapseRules: Sendable {
  public let maxConsecutiveBeforeFoundationLoss: Int

  private var consecutiveCollapses = 0
  private var reviveAvailable = false

  public init(maxConsecutiveBeforeFoundationLoss: Int = 3) {
    self.maxConsecutiveBeforeFoundationLoss = maxConsecutiveBeforeFoundationLoss
  }

  public mutating func resolveCollapse(cause: CollapseCause, tower: inout TowerState) -> CollapseOutcome {
    let removed = tower.removeTop()
    consecutiveCollapses += 1
    reviveAvailable = removed != nil
    return CollapseOutcome(
      removedDistrict: removed,
      towerEmptyAfter: tower.districts.isEmpty,
      consecutiveCollapses: consecutiveCollapses
    )
  }

  public mutating func registerPlacement() {
    consecutiveCollapses = 0
  }

  public func shouldOfferRevive(after outcome: CollapseOutcome) -> Bool {
    reviveAvailable && !outcome.towerEmptyAfter
  }

  public mutating func revive() -> Bool {
    guard reviveAvailable else { return false }
    reviveAvailable = false
    consecutiveCollapses = max(0, consecutiveCollapses - 1)
    return true
  }

  /// Player declined the revive offer (or it expired).
  public mutating func declineRevive() {
    reviveAvailable = false
  }

  public func foundationLost() -> Bool {
    consecutiveCollapses >= maxConsecutiveBeforeFoundationLoss
  }
}