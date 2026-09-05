import Foundation

/// Market stock entries (spec §12 Market tab). Deterministic daily rotation.
public struct MarketEntry: Sendable, Identifiable, Codable, Equatable {
  public let id: String
  public let title: String
  public let subtitle: String
  public let currency: Currency
  public let price: Int
  public let kind: MarketItemKind

  public init(
    id: String, title: String, subtitle: String, currency: Currency, price: Int,
    kind: MarketItemKind
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.currency = currency
    self.price = price
    self.kind = kind
  }
}

public enum MarketItemKind: Sendable, Codable, Equatable {
  case gearBox(rarity: Rarity)
  case goldPack(amount: Int)
  case xpPotion(amount: Int)  // v1: converts to hero XP is deferred; grants account XP placeholder
  case gemBundle(amount: Int)  // bought WITH GOLD (rare discounted exchange)

  /// Convenience for tests and UI filtering.
  public var isGearBox: Bool {
    if case .gearBox = self { return true }
    return false
  }
}

/// The in-game Market (spec §12): 4 tabs, daily rotating stock with one free item.
public struct MarketSystem: Sendable {
  public init() {}

  /// Today's stock — deterministic per calendar day (same stock all day, rotates daily).
  public static func dailyStock(for date: Date = Date()) -> [MarketEntry] {
    let day = Calendar(identifier: .gregorian).ordinality(of: .day, in: .era, for: date) ?? 0
    var rng = SeededGenerator(seed: UInt64(day * 7919))
    var stock: [MarketEntry] = []

    // Always: one free item
    stock.append(
      MarketEntry(
        id: "free-daily", title: "Free Gear Box", subtitle: "One free box every day",
        currency: .gold, price: 0, kind: .gearBox(rarity: .common)))

    // Rotating: 3 gear boxes at escalating rarity
    let rarities: [Rarity] = [.common, .rare, .epic, .legendary]
    let prices = [2000, 6000, 15000, 40000]
    for index in 0..<3 {
      let rarity = rarities[(day + index * 2 + Int(rng.next() % 2)) % rarities.count]
      stock.append(
        MarketEntry(
          id: "gear-\(index)-\(rarity)", title: "\(rarity) Gear Box",
          subtitle: "Random \(rarity) item", currency: .gold, price: prices[rarity.rawValue],
          kind: .gearBox(rarity: rarity)))
    }

    // Rotating: 2 gold packs (bought with gems)
    let gemPacks: [(gems: Int, gold: Int)] = [(10, 5000), (25, 14000)]
    for (packIndex, pack) in gemPacks.enumerated() {
      stock.append(
        MarketEntry(
          id: "gold-\(packIndex)", title: "Gold Pack", subtitle: "+\(pack.gold) gold", currency: .gems,
          price: pack.gems, kind: .goldPack(amount: pack.gold)))
    }

    // One rare gem-for-gold exchange
    stock.append(
      MarketEntry(
        id: "gem-exchange", title: "Gem Exchange", subtitle: "+5 gems", currency: .gold,
        price: 10000, kind: .gemBundle(amount: 5)))

    return stock
  }
}
