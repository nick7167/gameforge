import SwiftUI
import GameCore

/// In-run HUD: lean meter, Coins, height. Minimal — the tower is the screen.
struct GameHUD: View {
  let lean: Double
  let coins: Int
  let height: Int
  let windIncoming: Bool

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Label("\(coins)", systemImage: "circlebadge.fill")
          .font(.headline.monospacedDigit())
        Spacer()
        Text("\(height) m")
          .font(.headline.monospacedDigit())
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(.gray.opacity(0.25))
          Capsule()
            .fill(lean > 0.7 ? Color.red : Color.orange)
            .frame(width: proxy.size.width * lean)
        }
      }
      .frame(height: 8)
      if windIncoming {
        Label("Wind incoming!", systemImage: "wind")
          .font(.footnote.bold())
          .foregroundStyle(.yellow)
          .transition(.opacity)
      }
    }
    .padding(.horizontal)
    .animation(.easeInOut, value: windIncoming)
  }
}
