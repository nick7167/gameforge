import SwiftUI
import GameCore

/// Run summary with milestone celebration and share (Poly Bridge lesson:
/// the collapse/win moment is the viral content).
struct GameOverScreen: View {
    let summary: SkylineSession.RunSummary
    let onReplay: () -> Void
    let onMenu: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            if let milestone = summary.milestone {
                Text("🏆 \(milestone.rawValue.capitalized) reached!")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
            }
            Text("\(summary.height) m")
                .font(.system(size: 64, weight: .bold, design: .rounded))
            HStack(spacing: 32) {
                VStack {
                    Text("\(summary.coinsEarned)").font(.title2.bold())
                    Text("Coins").font(.caption)
                }
                VStack {
                    Text("\(summary.xpEarned)").font(.title2.bold())
                    Text("XP").font(.caption)
                }
            }
            ShareLink(item: "I built a \(summary.height) m skyline in Skyline Stack! 🏙️") {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button("Build again", action: onReplay)
                .buttonStyle(.borderedProminent)
            Button("Menu", action: onMenu)
        }
        .padding()
    }
}
