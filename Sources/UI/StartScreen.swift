import SwiftUI

/// Minimal Emberfall Realms start screen (placeholder shell — Plan 2
/// replaces it with the full menu). Gold-on-dark styling per the art
/// direction (design spec §13): dark rich background, gold gradient
/// title, chunky gold CTA.
struct StartScreen: View {
  @ObservedObject var model: EmberGameModel

  private let goldLight = Color(red: 1.00, green: 0.84, blue: 0.44)
  private let goldDeep = Color(red: 0.85, green: 0.62, blue: 0.25)
  private let emberDark = Color(red: 0.07, green: 0.05, blue: 0.10)

  var body: some View {
    ZStack {
      emberDark.ignoresSafeArea()
      VStack(spacing: 20) {
        Spacer()
        titleBlock
        Spacer()
        playButton
        Text("Battle coming soon")
          .font(.footnote)
          .foregroundColor(Color(red: 0.72, green: 0.66, blue: 0.55))
        Spacer()
        Text("Chapter 1 · Duskwood Vale")
          .font(.caption)
          .foregroundColor(Color(red: 0.55, green: 0.50, blue: 0.42))
      }
      .padding()
    }
  }

  private var titleBlock: some View {
    VStack(spacing: 8) {
      Text("EMBERFALL")
        .font(.system(size: 44, weight: .black, design: .serif))
        .foregroundStyle(
          LinearGradient(colors: [goldLight, goldDeep], startPoint: .top, endPoint: .bottom)
        )
      Text("REALMS")
        .font(.system(size: 26, weight: .bold, design: .serif))
        .tracking(10)
        .foregroundColor(goldDeep)
    }
  }

  private var playButton: some View {
    // Placeholder CTA — Plan 2 wires the real battle flow.
    Button {
    } label: {
      Text("TAP TO PLAY")
        .font(.system(size: 22, weight: .heavy))
        .tracking(2)
        .foregroundColor(.black)
        .padding(.horizontal, 44)
        .padding(.vertical, 16)
        .background(
          Capsule().fill(LinearGradient(colors: [goldLight, goldDeep], startPoint: .top, endPoint: .bottom))
        )
    }
  }
}
