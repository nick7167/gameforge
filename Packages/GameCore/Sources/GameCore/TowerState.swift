import Foundation

/// The tower: an ordered stack of districts with lean/stability bookkeeping.
///
/// This is the RULES layer. The SceneKit layer runs the actual rigid-body
/// simulation and reports outcomes here; GameCore decides what is legal,
/// what it costs, and when the rules say "collapse".
public struct TowerState: Sendable {
  public private(set) var districts: [District] = []
  public private(set) var curedDistrictIDs: Set<UInt64> = []
  /// 0…1. Accumulates from off-center placements; cured districts stop contributing.
  public private(set) var lean: Double = 0

  private let rules: PlacementRules
  /// Districts become cured this many placements after being placed.
  private let curePlacements: Int

  public init(rules: PlacementRules = PlacementRules(), curePlacements: Int = 5) {
    self.rules = rules
    self.curePlacements = curePlacements
  }

  public func type(for district: District) -> DistrictType? {
    DistrictType.v1Catalog.first { $0.id == district.typeID }
  }

  private func footprint(of typeID: String) -> Int {
    DistrictType.v1Catalog.first { $0.id == typeID }?.footprint ?? 2
  }

  private func weight(of typeID: String) -> Int {
    DistrictType.v1Catalog.first { $0.id == typeID }?.weight ?? 2
  }

  public func canPlace(_ type: DistrictType, at origin: GridPoint) -> Bool {
    guard let top = districts.last else { return true }
    return rules.isSupported(
      footprint: type.footprint,
      origin: origin,
      belowFootprint: footprint(of: top.typeID),
      belowOrigin: top.gridOrigin
    )
  }

  public enum PlaceResult: Equatable, Sendable {
    case placed(perfect: Bool)
    case rejected(reason: String)
  }

  public mutating func place(_ type: DistrictType, at origin: GridPoint, tick: UInt64) -> PlaceResult {
    guard canPlace(type, at: origin) else {
      return .rejected(reason: "unsupported")
    }
    let snapped = rules.snap(origin)
    let belowOrigin = districts.last?.gridOrigin ?? GridPoint(x: 0, z: 0)
    let offset = snapped - belowOrigin
    let perfect = rules.isPerfect(offset: offset)
    districts.append(District(typeID: type.id, gridOrigin: snapped, placedAtTick: tick))
    // Lean: off-center mass adds; recent good placements decay it slightly.
    let contribution = rules.alignmentError(offset: offset) * Double(type.weight) * 0.05
    lean = min(1.0, max(0, lean * 0.9 - (perfect ? 0.02 : 0) + contribution))
    return .placed(perfect: perfect)
  }

  /// Cures districts placed more than `curePlacements` placements ago.
  /// Cured districts stop contributing to lean (their weight is settled).
  public mutating func cure(tick: UInt64) {
    guard let newest = districts.map(\.placedAtTick).max() else { return }
    for district in districts where newest - district.placedAtTick >= UInt64(curePlacements) {
      curedDistrictIDs.insert(district.placedAtTick)
    }
  }

  /// Stability = 1 minus the lean contributed by uncured districts.
  public func stabilityScore() -> Double {
    guard !districts.isEmpty else { return 1.0 }
    let uncured = districts.filter { !curedDistrictIDs.contains($0.placedAtTick) }
    guard !uncured.isEmpty else { return 1.0 }
    let base = districts.first?.gridOrigin ?? GridPoint(x: 0, z: 0)
    let uncuredLean = uncured.reduce(0.0) { sum, district in
      let districtWeight = Double(weight(of: district.typeID))
      let error = rules.alignmentError(offset: district.gridOrigin - base)
      return sum + error * districtWeight * 0.05
    }
    return max(0, 1.0 - min(1.0, uncuredLean))
  }

  public mutating func removeTop() -> District? {
    guard let top = districts.popLast() else { return nil }
    curedDistrictIDs.remove(top.placedAtTick)
    return top
  }
}
