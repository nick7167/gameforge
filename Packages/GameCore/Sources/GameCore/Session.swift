import Foundation

/// High-level phase of a game session.
public enum GamePhase: String, Codable, Sendable {
    case menu
    case playing
    case paused
    case finished
}

/// A snapshot of a session's progress, suitable for persistence.
public struct SessionState: Codable, Equatable, Sendable {
    public var phase: GamePhase
    public var score: Int
    public var bestScore: Int

    public init(phase: GamePhase, score: Int, bestScore: Int) {
        self.phase = phase
        self.score = score
        self.bestScore = bestScore
    }
}

/// Mutable state for a single play session.
///
/// Keep all game rules and state transitions in `GameCore` so they can be
/// unit-tested locally without a simulator. View layers should drive this
/// type and render its state, never own gameplay state themselves.
public struct Session: Sendable {
    public private(set) var state: SessionState

    public init(bestScore: Int = 0) {
        state = SessionState(phase: .menu, score: 0, bestScore: bestScore)
    }

    public init(state: SessionState) {
        self.state = state
    }

    public var phase: GamePhase { state.phase }
    public var score: Int { state.score }
    public var bestScore: Int { state.bestScore }

    /// Begins a fresh round.
    public mutating func start() {
        state.score = 0
        state.phase = .playing
    }

    /// Adds points earned during play.
    public mutating func addScore(_ points: Int) {
        precondition(points >= 0, "Score cannot go backwards during play")
        state.score += points
    }

    /// Pauses an in-progress round.
    public mutating func pause() {
        guard state.phase == .playing else { return }
        state.phase = .paused
    }

    /// Resumes a paused round.
    public mutating func resume() {
        guard state.phase == .paused else { return }
        state.phase = .playing
    }

    /// Ends the current round, updating the best score.
    public mutating func finish() {
        state.bestScore = max(state.score, state.bestScore)
        state.phase = .finished
    }

    /// Returns to the menu.
    public mutating func backToMenu() {
        state.phase = .menu
    }
}
