import Foundation

/// Coins, rent, combo bonuses and helper inventory.
public struct Economy: Sendable {
  public enum Helper: String, Codable, CaseIterable, Sendable {
    case stabilizer, windBarrier, foundationReinforce, extraRevive
  }

  public struct CoinPack: Sendable {
    public static let iapTiers: [(id: String, coins: Int, priceUSD: Double)] = [
      ("coins.small", 100, 0.99),
      ("coins.medium", 350, 2.99),
      ("coins.large", 700, 4.99),
    ]
  }

  public static let perfectBonus = 5

  public private(set) var coins: Int
  public private(set) var inventory: [Helper: Int] = [:]

  public init(startingCoins: Int) {
    coins = startingCoins
  }

  /// Rent for a milestone: 1 Coin per housed district, plus the perfect
  /// bonus scaled by streak (×1.0 at streak 1, +0.5 per extra step, cap ×2).
  /// Streak 0 means no perfect placements this milestone → no bonus.
  @discardableResult
  public mutating func earnRent(districtsHoused: Int, perfectStreak: Int) -> Int {
    let bonus: Int
    if perfectStreak > 0 {
      let multiplier = 1.0 + 0.5 * Double(min(perfectStreak - 1, 2))
      bonus = Int((Double(Self.perfectBonus) * multiplier).rounded())
    } else {
      bonus = 0
    }
    let earned = districtsHoused + bonus
    coins += earned
    return earned
  }

  @discardableResult
  public mutating func spend(_ cost: Int) -> Bool {
    guard coins >= cost else { return false }
    coins -= cost
    return true
  }

  public static func price(for helper: Helper) -> Int {
    switch helper {
    case .stabilizer: 30
    case .windBarrier: 25
    case .foundationReinforce: 40
    case .extraRevive: 50
    }
  }

  @discardableResult
  public mutating func buy(_ helper: Helper) -> Bool {
    guard spend(Self.price(for: helper)) else { return false }
    inventory[helper, default: 0] += 1
    return true
  }

  @discardableResult
  public mutating func use(_ helper: Helper) -> Bool {
    guard let count = inventory[helper], count > 0 else { return false }
    inventory[helper] = count - 1
    return true
  }
}