import GameCore
import SwiftUI
import SpriteKit

/// Bridges a SpriteKit scene into SwiftUI.
///
/// The scene reports game events through `onEvent`; all callbacks arrive on
/// the main actor. Gameplay *rules* stay in `GameCore` — this layer only
/// translates rendering into events.
struct GameView: View {
    let session: Session
    let onEvent: (DemoGameEvent) -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: makeScene())
                .ignoresSafeArea()
            VStack {
                Text("Score: \(session.score)")
                    .font(.title2.bold())
                    .monospacedDigit()
                    .padding(.top, 8)
                Spacer()
            }
        }
        .overlay(alignment: .topLeading) {
            Button("Menu") { onExit() }
                .padding()
        }
    }

    @MainActor
    private func makeScene() -> SKScene {
        let scene = DemoScene(size: UIScreen.main.bounds.size)
        scene.onEvent = onEvent
        scene.scaleMode = .resizeFill
        return scene
    }
}
