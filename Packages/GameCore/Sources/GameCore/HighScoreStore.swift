import Foundation

/// Persists high scores. Implement with `UserDefaults`, files, or a database
/// in the app layer; `GameCore` only defines the contract.
public protocol HighScoreStore: Sendable {
    func bestScore(for gameID: String) -> Int
    func record(score: Int, for gameID: String) -> Bool
}

/// Thread-safe in-memory implementation, useful for tests and previews.
public final class InMemoryHighScoreStore: HighScoreStore, @unchecked Sendable {
    private let lock = NSLock()
    private var scores: [String: Int]

    public init(initial: [String: Int] = [:]) {
        scores = initial
    }

    public func bestScore(for gameID: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return scores[gameID] ?? 0
    }

    /// Records a score; returns true when it becomes the new best.
    @discardableResult
    public func record(score: Int, for gameID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let previous = scores[gameID] ?? 0
        guard score > previous else { return false }
        scores[gameID] = score
        return true
    }
}
