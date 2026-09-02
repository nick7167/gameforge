import GameKit
import UIKit

/// Game Center leaderboards for the daily height challenge. All calls
/// no-op gracefully when Game Center is unavailable (simulator, signed out).
@MainActor
final class GameCenterService {
  static let leaderboardID = "daily.height"

  func authenticate() async {
    let player = GKLocalPlayer.local
    guard !player.isAuthenticated else { return }
    player.authenticateHandler = { _, _ in }
  }

  func submitDailyHeight(_ height: Int) async {
    guard GKLocalPlayer.local.isAuthenticated else { return }
    let score = GKScore(leaderboardIdentifier: Self.leaderboardID)
    score.value = Int64(height)
    try? await GKScore.report([score])
  }

  func showLeaderboard() {
    guard GKLocalPlayer.local.isAuthenticated else { return }
    let controller = GKGameCenterViewController(
      leaderboardID: Self.leaderboardID,
      playerScope: .global,
      timeScope: .today
    )
    Self.topViewController()?.present(controller, animated: true)
  }

  private static func topViewController() -> UIViewController? {
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
      .first
  }
}
