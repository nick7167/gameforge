import Foundation
import UIKit
import RevenueCat

/// Rewarded-video abstraction. The game must run without ads configured
/// (simulator, CI, ad-load failures) — hence the no-op implementation.
protocol RewardedAdService: Sendable {
  func isReady() async -> Bool
  /// Shows a rewarded ad. Returns true only if the reward was earned.
  func show(from viewController: UIViewController?) async -> Bool
}

/// Used when ads are unavailable: revive offers fall back to the
/// "decline" path and helper-earn buttons hide themselves.
final class NoOpAdService: RewardedAdService {
  func isReady() async -> Bool { false }
  func show(from viewController: UIViewController?) async -> Bool { false }
}

/// AdMob rewarded video. Uses Google's official test unit ID until the
/// owner's AdMob account is set up.
final class AdMobService: NSObject, RewardedAdService, @unchecked Sendable {
  static let testUnitID = "ca-app-pub-3940256099942544/1712485313"

  private var rewarded: RewardedAd?
  private var loadedUnitID: String?

  static func configureIfNeeded() {
    if Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") != nil {
      MobileAds.shared.start(completionHandler: nil)
    }
  }

  func isReady() async -> Bool {
    await load()
    return rewarded != nil
  }

  private func load() async {
    let unitID = Self.testUnitID
    if loadedUnitID == unitID, rewarded != nil { return }
    rewarded = try? await RewardedAd.load(with: unitID, request: Request())
    loadedUnitID = unitID
  }

  func show(from viewController: UIViewController?) async -> Bool {
    guard let rewarded else { return false }
    let presented = rewarded.present(from: viewController) { _ in }
    return presented
  }
}
