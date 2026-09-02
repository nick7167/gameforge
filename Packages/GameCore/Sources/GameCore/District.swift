import Foundation

/// A kind of placeable district block.
public struct DistrictType: Codable, Hashable, Sendable {
  public let id: String
  public let displayName: String
  /// Grid cells per side (1–3).
  public let footprint: Int
  /// Physics mass proxy (1–5).
  public let weight: Int
  public let rentPerMilestone: Int
  public let requiredLevel: Int

  public init(id: String, displayName: String, footprint: Int, weight: Int, rentPerMilestone: Int, requiredLevel: Int) {
    self.id = id
    self.displayName = displayName
    self.footprint = footprint
    self.weight = weight
    self.rentPerMilestone = rentPerMilestone
    self.requiredLevel = requiredLevel
  }
}

extension DistrictType {
  /// The eight v1 district types. Unlock order = array order.
  public static let v1Catalog: [DistrictType] = [
    DistrictType(id: "homes", displayName: "Homes", footprint: 2, weight: 2, rentPerMilestone: 2, requiredLevel: 1),
    DistrictType(id: "shops", displayName: "Shops", footprint: 2, weight: 2, rentPerMilestone: 3, requiredLevel: 1),
    DistrictType(id: "park", displayName: "Park", footprint: 3, weight: 1, rentPerMilestone: 1, requiredLevel: 1),
    DistrictType(id: "office", displayName: "Offices", footprint: 2, weight: 3, rentPerMilestone: 4, requiredLevel: 2),
    DistrictType(id: "tower", displayName: "Tower", footprint: 1, weight: 4, rentPerMilestone: 5, requiredLevel: 3),
    DistrictType(id: "temple", displayName: "Temple", footprint: 3, weight: 2, rentPerMilestone: 4, requiredLevel: 4),
    DistrictType(id: "garden", displayName: "Sky Garden", footprint: 2, weight: 1, rentPerMilestone: 3, requiredLevel: 5),
    DistrictType(id: "observatory", displayName: "Observatory", footprint: 1, weight: 3, rentPerMilestone: 6, requiredLevel: 6),
  ]
}

/// One placed district instance on the tower.
public struct District: Codable, Hashable, Sendable {
  public let typeID: String
  public var gridOrigin: GridPoint
  public let placedAtTick: UInt64

  public init(typeID: String, gridOrigin: GridPoint, placedAtTick: UInt64) {
    self.typeID = typeID
    self.gridOrigin = gridOrigin
    self.placedAtTick = placedAtTick
  }
}

/// XP → level mapping. Level N requires (N-1)*100 XP.
public enum UnlockLadder {
  public static func levelForXP(_ xp: Int) -> Int {
    xp / 100 + 1
  }

  public static func unlockedTypes(level: Int) -> [DistrictType] {
    DistrictType.v1Catalog.filter { $0.requiredLevel <= level }
  }
}

/// Integer grid coordinate on a tower level. Origin (0,0) = center.
/// (Full placement math arrives with PlacementRules in a later task.)
public struct GridPoint: Codable, Hashable, Sendable {
  public var x: Int
  public var z: Int

  public init(x: Int, z: Int) {
    self.x = x
    self.z = z
  }
}