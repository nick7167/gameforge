import Foundation

/// Date-seeded daily challenge. Fully offline: the seed derives from the
/// calendar day, so every device sees the same challenge without a server.
public struct DailyChallenge: Sendable {
  public let seed: UInt64
  public let allowedTypeIDs: Set<String>
  public let targetHeight: Int
  public let parPlacements: Int

  public init(date: Date, calendar: Calendar = .current) {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    var hasher = Hasher()
    hasher.combine(components.year)
    hasher.combine(components.month)
    hasher.combine(components.day)
    seed = UInt64(bitPattern: Int64(hasher.finalize()))

    var rng = SeededGenerator(seed: seed)
    let catalog = DistrictType.v1Catalog
    let count = (3...5).randomElement(using: &rng)!
    allowedTypeIDs = Set((0..<count).map { catalog[$0 % catalog.count].id })
    targetHeight = (20...60).randomElement(using: &rng)!
    parPlacements = targetHeight / 2 + 5
  }
}
