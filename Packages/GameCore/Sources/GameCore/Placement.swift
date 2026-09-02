import Foundation

/// Integer grid coordinate on a tower level. Origin (0,0) = center.
public struct GridPoint: Codable, Hashable, Sendable {
  public var x: Int
  public var z: Int

  public init(x: Int, z: Int) {
    self.x = x
    self.z = z
  }

  public static func + (lhs: GridPoint, rhs: GridPoint) -> GridPoint {
    GridPoint(x: lhs.x + rhs.x, z: lhs.z + rhs.z)
  }

  public static func - (lhs: GridPoint, rhs: GridPoint) -> GridPoint {
    GridPoint(x: lhs.x - rhs.x, z: lhs.z - rhs.z)
  }
}

/// Placement legality and scoring math. Snap is input-only; physics is honest.
public struct PlacementRules: Sendable {
  public let gridExtent: Int
  /// Euclidean cell distance counted as "perfect" placement.
  public static let perfectThreshold: Double = 0.15
  /// Max cells a district may overhang the district below.
  public static let maxOverhang: Int = 2

  private var half: Int { gridExtent / 2 }

  public init(gridExtent: Int = 7) {
    self.gridExtent = gridExtent
  }

  public func snap(_ point: GridPoint) -> GridPoint {
    GridPoint(x: min(max(point.x, -half), half), z: min(max(point.z, -half), half))
  }

  public func alignmentError(offset: GridPoint) -> Double {
    let dx = Double(offset.x), dz = Double(offset.z)
    return (dx * dx + dz * dz).squareRoot()
  }

  public func isPerfect(offset: GridPoint) -> Bool {
    alignmentError(offset: offset) <= Self.perfectThreshold
  }

  /// Cell span [start, end] on one axis for a footprint centered on origin.
  private func span(_ footprint: Int, _ origin: Int) -> ClosedRange<Int> {
    let start = origin - footprint / 2
    return start...(start + footprint - 1)
  }

  /// True if the new district overlaps the one below by at least one cell
  /// and does not overhang beyond `maxOverhang` cells past its edge.
  public func isSupported(footprint: Int, origin: GridPoint, belowFootprint: Int, belowOrigin: GridPoint) -> Bool {
    func overlaps(_ a: ClosedRange<Int>, _ b: ClosedRange<Int>) -> Bool {
      a.lowerBound <= b.upperBound && b.lowerBound <= a.upperBound
    }
    let xSpan = span(footprint, origin.x)
    let zSpan = span(footprint, origin.z)
    let belowX = span(belowFootprint, belowOrigin.x)
    let belowZ = span(belowFootprint, belowOrigin.z)
    guard overlaps(xSpan, belowX), overlaps(zSpan, belowZ) else { return false }
    let xOverhang = max(0, max(belowX.lowerBound - xSpan.lowerBound, xSpan.upperBound - belowX.upperBound))
    let zOverhang = max(0, max(belowZ.lowerBound - zSpan.lowerBound, zSpan.upperBound - belowZ.upperBound))
    return xOverhang <= Self.maxOverhang && zOverhang <= Self.maxOverhang
  }
}
