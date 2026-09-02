import SwiftUI

struct StartScreen: View {
    let bestScore: Int
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("GameForge")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Foundation build — the game comes next.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onStart) {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
            if bestScore > 0 {
                Text("Best: \(bestScore)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.10, green: 0.11, blue: 0.20).ignoresSafeArea())
    }
}

#Preview {
    StartScreen(bestScore: 0, onStart: {})
}
