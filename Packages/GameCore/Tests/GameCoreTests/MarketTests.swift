import Foundation
import Testing
@testable import GameCore

@Suite struct MarketTests {
  // MARK: - Stock

  @Test func marketStockDeterministicPerDay() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(MarketSystem.dailyStock(for: date) == MarketSystem.dailyStock(for: date))
  }

  @Test func marketStockRotatesAcrossDays() {
    let dayA = Date(timeIntervalSince1970: 1_700_000_000)
    let dayB = Date(timeIntervalSince1970: 1_700_000_000 + 86_400)
    // Same shape (one free + 3 gear + 2 gold + 1 exchange) every day.
    for date in [dayA, dayB] {
      let stock = MarketSystem.dailyStock(for: date)
      #expect(stock.count == 7)
      #expect(stock.contains { $0.id == "free-daily" })
      #expect(stock.filter { $0.kind.isGearBox }.count == 4)  // free + 3 rotating
      #expect(stock.filter { $0.kind == .goldPack(amount: 5000) || $0.kind == .goldPack(amount: 14000) }.count == 2)
      #expect(stock.contains { $0.id == "gem-exchange" })
    }
  }

  @Test func freeDailyItemIsFree() {
    let free = MarketSystem.dailyStock().first { $0.id == "free-daily" }
    #expect(free?.price == 0)
  }

  // MARK: - Buying

  @Test func buyGearBoxSpendsGoldAndAddsItem() {
    var session = EmberSession(profile: .new(), rngSeed: 42) {
      $0.wallet.add(.gold, 50_000)
    }
    // Paid rotating gear boxes are gold-priced; the free box is handled elsewhere.
    let entry = MarketSystem.dailyStock().first { $0.kind.isGearBox && $0.price > 0 }
    #expect(entry != nil)
    guard let entry else { return }
    let before = session.profile.gearInventory.count
    let goldBefore = session.profile.wallet.balance(of: .gold)
    #expect(session.buyMarket(entryID: entry.id) == true)
    #expect(session.profile.gearInventory.count == before + 1)
    #expect(session.profile.wallet.balance(of: .gold) == goldBefore - entry.price)
  }

  @Test func buyGearBoxFailsWhenBroke() {
    // Zero the wallet so the purchase must fail.
    var session = EmberSession(profile: .new(), rngSeed: 42) {
      $0.wallet = Wallet(balances: [:])
    }
    let entry = MarketSystem.dailyStock().first { $0.kind.isGearBox && $0.price > 0 }
    #expect(entry != nil)
    guard let entry else { return }
    #expect(session.buyMarket(entryID: entry.id) == false)
    #expect(session.profile.gearInventory.isEmpty)
  }

  @Test func freeMarketItemOncePerDay() {
    var session = EmberSession()
    #expect(session.freeMarketClaimedToday() == false)
    #expect(session.buyMarket(entryID: "free-daily") == true)
    #expect(session.freeMarketClaimedToday() == true)
    #expect(session.buyMarket(entryID: "free-daily") == false)
  }

  @Test func buyGoldPackSpendsGemsAddsGold() {
    var session = EmberSession()  // new profile: 300 gems
    let beforeGems = session.profile.wallet.balance(of: .gems)
    let beforeGold = session.profile.wallet.balance(of: .gold)
    #expect(session.buyMarket(entryID: "gold-0") == true)
    #expect(session.profile.wallet.balance(of: .gems) == beforeGems - 10)
    #expect(session.profile.wallet.balance(of: .gold) == beforeGold + 5000)
  }

  @Test func buyGemExchangeAddsGems() {
    var session = EmberSession(profile: .new(), rngSeed: 42) {
      $0.wallet.add(.gold, 10_000)
    }
    let beforeGems = session.profile.wallet.balance(of: .gems)
    #expect(session.buyMarket(entryID: "gem-exchange") == true)
    #expect(session.profile.wallet.balance(of: .gems) == beforeGems + 5)
  }

  @Test func buyUnknownEntryFails() {
    var session = EmberSession()
    #expect(session.buyMarket(entryID: "nope") == false)
  }

  @Test func grantCurrencyAddsAnyCurrency() {
    var session = EmberSession()
    session.grantCurrency(.gold, 500)
    session.grantCurrency(.gems, -10)  // ignored: must be positive
    #expect(session.profile.wallet.balance(of: .gold) == 2500)
    #expect(session.profile.wallet.balance(of: .gems) == 300)
  }
}
