import GameCore
import SwiftUI

/// Owns the app-level navigation between menu and gameplay.
///
/// All gameplay state lives in `Session` (GameCore); this view only drives
/// and renders it.
struct RootView: View {
    @State private var session = Session()
    @State private var bestScores = InMemoryHighScoreStore()

    var body: some View {
        switch session.phase {
        case .menu:
            StartScreen(
                bestScore: session.bestScore,
                onStart: {
                    session.start()
                }
            )
        case .playing, .paused:
            GameView(session: session) { event in
                switch event {
                case .scored(let points):
                    session.addScore(points)
                case .ended:
                    session.finish()
                    bestScores.record(score: session.score, for: "demo")
                }
            } onExit: {
                session.backToMenu()
            }
        case .finished:
            GameOverScreen(
                score: session.score,
                bestScore: session.bestScore,
                onReplay: {
                    session.start()
                },
                onMenu: {
                    session.backToMenu()
                }
            )
        }
    }
}

#Preview {
    RootView()
}
