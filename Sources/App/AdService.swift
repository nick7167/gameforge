import Foundation
import UIKit

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
