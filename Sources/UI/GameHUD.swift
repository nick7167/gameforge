import SwiftUI
import GameCore

/// In-run HUD: playful chips, big mono numbers, lean meter with danger
/// pulse, quit button. Rounded + colorful per mobile-app-ui-design skill.
struct GameHUD: View {
  let lean: Double
  let coins: Int
  let height: Int
  let windIncoming: Bool
  var onQuit: (() -> Void)?

  private var leanColor: Color {
    lean > 0.7 ? .red : lean > 0.4 ? .orange : .mint
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 8) {
        StatChip(icon: "circlebadge.fill", text: "\(coins)", color: .orange)
        Spacer()
        StatChip(icon: "building.2.fill", text: "\(height)m", color: .blue)
        if let onQuit {
          Button(action: onQuit) {
            Image(systemName: "xmark")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(.white)
              .frame(width: 44, height: 44)
              .background(Circle().fill(.black.opacity(0.35)))
          }
          .accessibilityIdentifier("hud-quit-button")
        }
      }

      // Lean meter — big, rounded, with label.
      VStack(alignment: .leading, spacing: 4) {
        Text(lean > 0.7 ? "DANGER!" : "Stability")
          .font(.caption2.weight(.heavy))
          .foregroundStyle(lean > 0.7 ? .red : .white.opacity(0.75))
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(.black.opacity(0.3))
            Capsule()
              .fill(leanColor)
              .frame(width: max(16, proxy.size.width * lean))
              .animation(.spring(response: 0.3), value: lean)
          }
        }
        .frame(height: 14)
      }

      if windIncoming {
        Label("WIND INCOMING!", systemImage: "wind")
          .font(.callout.weight(.heavy))
          .foregroundStyle(.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(Capsule().fill(.teal.opacity(0.9)))
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .padding(.horizontal, 16)
    .animation(.spring(response: 0.35), value: windIncoming)
    .animation(.spring(response: 0.35), value: lean)
  }
}

/// Rounded stat chip: icon + mono number on a translucent pill.
private struct StatChip: View {
  let icon: String
  let text: String
  let color: Color

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(color)
      Text(text)
        .font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit())
        .foregroundStyle(.white)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Capsule().fill(.black.opacity(0.35)))
  }
}
