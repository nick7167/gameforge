import SwiftUI

struct GameOverScreen: View {
    let score: Int
    let bestScore: Int
    let onReplay: () -> Void
    let onMenu: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Round over")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("Score: \(score)")
                .font(.title2.monospacedDigit())
            if score >= bestScore {
                Text("New best!")
                    .font(.headline)
                    .foregroundStyle(.yellow)
            } else {
                Text("Best: \(bestScore)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onReplay) {
                Text("Play again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            Button(action: onMenu) {
                Text("Back to menu")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.10, green: 0.11, blue: 0.20).ignoresSafeArea())
    }
}

#Preview {
    GameOverScreen(score: 12, bestScore: 20, onReplay: {}, onMenu: {})
}
