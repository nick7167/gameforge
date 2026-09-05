import GameCore
import SwiftUI

/// Root of the Emberfall Realms app. Holds the game facade; every screen
/// receives the model rather than touching GameCore directly.
struct RootView: View {
    @StateObject private var model = EmberGameModel()

    var body: some View {
        StartScreen(model: model)
    }
}
