import SwiftUI
import GameCore

/// The monetization moment: offered after a collapse that removed a district.
/// Always optional; auto-declines after the countdown (spec §6 hard rules).
struct ReviveOffer: View {
  @ObservedObject var model: SkylineGameModel
  @State private var secondsLeft = 10

  var body: some View {
    VStack(spacing: 20) {
      Text("The tower collapsed!")
        .font(.title.bold())
      Text("Stabilize and keep your district?")
        .font(.body)
      Button {
        Task { await model.reviveByAd() }
      } label: {
        Label("Watch ad — Stabilize & Continue", systemImage: "play.tv")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      if (model.session.economy.inventory[.stabilizer] ?? 0) > 0 {
        Button {
          _ = model.reviveByHelper()
        } label: {
          Label("Use Stabilizer", systemImage: "wand.and.stars")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      }
      Button("No thanks — lose the district") {
        model.abandonRevive()
      }
      .font(.footnote)
      Text("Continuing in \(secondsLeft)s…")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
    .padding(24)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    .padding()
    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
      if secondsLeft > 0 {
        secondsLeft -= 1
      } else {
        model.abandonRevive()
      }
    }
  }
}
