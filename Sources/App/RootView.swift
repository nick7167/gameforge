import GameCore
import SwiftUI

/// Root of the Emberfall Realms app. Holds the game facade; the hub is home,
/// battles take over the screen and hand control back via `onFinish`.
struct RootView: View {
  @StateObject private var model = EmberGameModel()
  @State private var inBattle = false

  var body: some View {
    if inBattle {
      BattleView(model: model, onFinish: { inBattle = false })
    } else {
      HubView(model: model, onStartBattle: { model.startBattle(); inBattle = true })
    }
  }
}
