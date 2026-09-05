import Foundation
import GameCore
import RevenueCat

/// Purchase facade. Backed by RevenueCat when an API key is configured;
/// degrades to a no-op otherwise so the game always runs.
@MainActor
final class PurchaseService: ObservableObject {
  static let removeAdsProductID = "dev.adrez.emberfall.removeads"
  static let growthBundleProductID = "dev.adrez.emberfall.growthbundle"
  static let monthlyCardProductID = "dev.adrez.emberfall.monthlycard"
  /// Gem pack product metadata.
  struct GemPack: Sendable {
    let id: String
    let gems: Int
    let priceUSD: String
  }
  /// Gem packs (consumables). `gems` is granted on purchase via `onGemsGranted`.
  static let gemPackProducts: [GemPack] = [
    GemPack(id: "dev.adrez.emberfall.gems.small", gems: 100, priceUSD: "$0.99"),
    GemPack(id: "dev.adrez.emberfall.gems.medium", gems: 550, priceUSD: "$4.99"),
    GemPack(id: "dev.adrez.emberfall.gems.large", gems: 1200, priceUSD: "$9.99"),
    GemPack(id: "dev.adrez.emberfall.gems.xl", gems: 3300, priceUSD: "$24.99"),
    GemPack(id: "dev.adrez.emberfall.gems.huge", gems: 7000, priceUSD: "$49.99"),
    GemPack(id: "dev.adrez.emberfall.gems.massive", gems: 15000, priceUSD: "$99.99")
  ]

  @Published private(set) var removeAdsOwned = false
  @Published private(set) var growthBundleOwned = false
  @Published private(set) var monthlyCardActive = false
  @Published private(set) var isConfigured = false

  private var onGemsGranted: ((Int) -> Void)?

  func configure(apiKey: String?, onGemsGranted: @escaping (Int) -> Void) {
    self.onGemsGranted = onGemsGranted
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
    growthBundleOwned =
      info?.nonSubscriptions.contains(where: { $0.productIdentifier == Self.growthBundleProductID }) == true
    monthlyCardActive = info?.entitlements["monthly_card"]?.isActive == true
  }

  func purchase(productID: String) async -> Bool {
    guard isConfigured else { return false }
    do {
      let products = try await Purchases.shared.products([productID])
      guard let product = products.first else { return false }
      let result = try await Purchases.shared.purchase(product: product)
      if result.userCancelled { return false }
      await refreshEntitlements()
      if let gems = Self.gemPackProducts.first(where: { $0.id == productID })?.gems {
        onGemsGranted?(gems)
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
}
