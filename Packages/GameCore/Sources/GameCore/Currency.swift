/// The four currencies (spec §8). No energy — campaign is ungated.
public enum Currency: String, Codable, Sendable, CaseIterable {
  case gold, gems, arenaTokens, questTokens
}

/// Player currency balances. Spending fails (returns false) when insufficient.
public struct Wallet: Sendable, Codable {
  public private(set) var balances: [Currency: Int]

  public init(balances: [Currency: Int] = [:]) {
    self.balances = balances
  }

  public func balance(of currency: Currency) -> Int { balances[currency] ?? 0 }

  public mutating func add(_ currency: Currency, _ amount: Int) {
    balances[currency, default: 0] += amount
  }

  @discardableResult
  public mutating func spend(_ currency: Currency, _ amount: Int) -> Bool {
    guard let current = balances[currency], current >= amount else { return false }
    balances[currency] = current - amount
    return true
  }
}
