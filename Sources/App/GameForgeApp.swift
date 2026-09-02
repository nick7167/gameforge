import SwiftUI

@main
struct GameForgeApp: App {
    init() {
        AdMobService.configureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
