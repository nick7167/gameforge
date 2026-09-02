import Foundation
import GameCore

/// Loads and saves the persistent skyline meta as JSON in Application Support.
enum SkylinePersistence {
  private static var fileURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return dir.appendingPathComponent("skyline-meta.json")
  }

  static func load() -> SkylineMeta? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(SkylineMeta.self, from: data)
  }

  static func save(_ meta: SkylineMeta) {
    guard let data = try? JSONEncoder().encode(meta) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  static func wipe() {
    try? FileManager.default.removeItem(at: fileURL)
  }
}