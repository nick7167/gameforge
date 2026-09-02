import Foundation
import GameCore

/// Purchase facade. Backed by RevenueCat when an API key is configured;
/// degrades to a no-op otherwise so the game always runs.
@MainActor
final class PurchaseService: ObservableObject {
  static let removeAdsProductID = "dev.adrez.skyline.removeads"
  static let coinPackProductIDs = [
    "dev.adrez.skyline.coins.small": 100,
    "dev.adrez.skyline.coins.medium": 350,
    "dev.adrez.skyline.coins.large": 700
  ]
  static let districtPackProductIDs: Set<String> = ["dev.adrez.skyline.pack.medieval"]

  @Published private(set) var removeAdsOwned = false
  @Published private(set) var ownedPackIDs: Set<String> = []
  @Published private(set) var isConfigured = false

  private var onCoinsGranted: ((Int) -> Void)?

  func configure(apiKey: String?, onCoinsGranted: @escaping (Int) -> Void) {
    self.onCoinsGranted = onCoinsGranted
    guard let apiKey, !apiKey.isEmpty else { return }
    isConfigured = true
    // Purchases.configure(with: apiKey) — wired with the SDK in Task 8.
  }

  func refreshEntitlements() async {
    guard isConfigured else { return }
    // Task 8: fetch CustomerInfo, set removeAdsOwned / ownedPackIDs.
  }

  func purchase(productID: String) async -> Bool {
    guard isConfigured else { return false }
    return false // Task 8 wires Purchases.shared.purchase(product:)
  }

  func restore() async {
    guard isConfigured else { return }
    await refreshEntitlements()
  }

  func grantCoinsIfPurchased(productID: String) -> Int? {
    guard let coins = Self.coinPackProductIDs[productID] else { return nil }
    onCoinsGranted(coins)
    return coins
  }
}