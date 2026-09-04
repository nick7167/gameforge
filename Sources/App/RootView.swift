import GameCore
import SwiftUI

/// Minimal placeholder shell for Emberfall Realms. Plan 2 replaces this
/// with the real game model and navigation; for now the app shows the
/// start screen and keeps a persisted PlayerProfile alive.
struct RootView: View {
    @State private var profile: PlayerProfile

    init() {
        _profile = State(initialValue: ProfilePersistence.load() ?? PlayerProfile.new())
    }

    var body: some View {
        StartScreen(profile: profile)
    }
}
