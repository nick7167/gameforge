import Foundation
import UIKit
import RevenueCat
import GoogleMobileAds

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
    guard let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
          appID.hasPrefix("ca-app-pub-"), appID.contains("~") else {
      // No valid app ID: do NOT touch the SDK at all. (The SDK also
      // auto-initializes when linked — but with a valid plist key now
      // guaranteed by project.yml, that path is safe too. See the v23
      // launch-crash postmortem: missing key → GADInvalidInitialization
      // exception at startup.)
      return
    }
    MobileAds.shared.start(completionHandler: nil)
  }

  func isReady() async -> Bool {
    await load()
    return rewarded != nil
  }

  private func load() async {
    let unitID = Self.testUnitID
    if loadedUnitID == unitID, rewarded != nil { return }
    do {
      rewarded = try await RewardedAd.load(with: unitID, request: Request())
      loadedUnitID = unitID
    } catch {
      rewarded = nil
      loadedUnitID = nil
    }
  }

  @MainActor
  func show(from viewController: UIViewController?) async -> Bool {
    guard let rewarded else { return false }
    // present(from:) returns Void; the reward handler fires when earned.
    // MainActor isolation keeps the non-Sendable RewardedAd and its callback
    // off concurrent executors (Swift 6 strict concurrency).
    return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      var resumed = false
      rewarded.present(from: viewController) {
        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: true)
      }
      // If presentation fails, no reward callback ever fires; the revive
      // flow treats a missing callback as decline (correct per spec).
      _ = resumed
    }
  }
}
