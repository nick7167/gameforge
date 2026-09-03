import SwiftUI
import GameCore

/// In-run HUD: lean meter, Coins, height. Minimal — the tower is the screen.
/// Uses translucent light material + dark text so it reads against the sky.
struct GameHUD: View {
  let lean: Double
  let coins: Int
  let height: Int
  let windIncoming: Bool

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 12) {
        Label("\(coins)", systemImage: "circlebadge.fill")
          .font(.headline.monospacedDigit())
          .foregroundStyle(.brown)
        Spacer()
        Text("\(height) m")
          .font(.headline.monospacedDigit())
          .foregroundStyle(.brown)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(.ultraThinMaterial, in: Capsule())
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(.ultraThinMaterial)
          Capsule()
            .fill(lean > 0.7 ? Color.red : Color.orange)
            .frame(width: proxy.size.width * lean)
        }
      }
      .frame(height: 10)
      if windIncoming {
        Label("Wind incoming!", systemImage: "wind")
          .font(.footnote.bold())
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(.red.opacity(0.8), in: Capsule())
          .transition(.opacity)
      }
    }
    .padding(.horizontal)
    .animation(.easeInOut, value: windIncoming)
  }
}
