import Foundation
import GameCore
import RevenueCat

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
    Purchases.logLevel = .warn
    let configuration = Configuration.Builder(withAPIKey: apiKey).build()
    Purchases.configure(with: configuration)
    isConfigured = true
  }

  func refreshEntitlements() async {
    guard isConfigured else { return }
    let info = try? await Purchases.shared.customerInfo()
    removeAdsOwned = info?.entitlements["remove_ads"]?.isActive == true
    ownedPackIDs = Set(info?.activeSubscriptions ?? [])
  }

  func purchase(productID: String) async -> Bool {
    guard isConfigured else { return false }
    do {
      let products = try await Purchases.shared.products([productID])
      guard let product = products.first else { return false }
      let result = try await Purchases.shared.purchase(product: product)
      if result.userCancelled { return false }
      await refreshEntitlements()
      if let coins = Self.coinPackProductIDs[productID] {
        onCoinsGranted?(coins)
      }
      if productID == Self.removeAdsProductID {
        removeAdsOwned = true
      }
      return true
    } catch {
      return false
    }
  }

  func restore() async {
    guard isConfigured else { return }
    _ = try? await Purchases.shared.restorePurchases()
    await refreshEntitlements()
  }

  func grantCoinsIfPurchased(productID: String) -> Int? {
    guard let coins = Self.coinPackProductIDs[productID] else { return nil }
    onCoinsGranted?(coins)
    return coins
  }
}
