import Foundation
import GameCore

/// Loads and saves the player profile as JSON in Application Support.
/// Load-or-default semantics: a missing or corrupt file yields `nil` and
/// the caller falls back to `PlayerProfile.new()`.
enum ProfilePersistence {
  private static var fileURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("emberfall-profile.json")
  }

  static func load() -> PlayerProfile? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(PlayerProfile.self, from: data)
  }

  static func save(_ profile: PlayerProfile) {
    guard let data = try? JSONEncoder().encode(profile) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  static func wipe() {
    try? FileManager.default.removeItem(at: fileURL)
  }
}
