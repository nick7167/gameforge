import GameCore
import SwiftUI

/// The full gameplay screen. Owns the game model via @ObservedObject so
/// every model change re-renders the HUD, banners, and overlays. (RootView's
/// @State does not subscribe to ObservableObject changes — that omission is
/// why the HUD froze at 0m/0 coins while the tower grew.)
struct GameplayView: View {
    @ObservedObject var model: SkylineGameModel
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            // Warm sky gradient behind the 3D scene.
            LinearGradient(
                colors: [Color(red: 0.23, green: 0.16, blue: 0.28),
                         Color(red: 0.85, green: 0.66, blue: 0.48),
                         Color(red: 0.98, green: 0.88, blue: 0.70)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            TowerSceneView(
                scene: model.scene,
                onFrame: { model.frameUpdate() },
                onTap: { model.dropPendingDistrict() }
            )
            .ignoresSafeArea()

            VStack {
                GameHUD(
                    lean: model.session.tower.lean,
                    coins: model.session.economy.coins,
                    height: model.heightMeters,
                    windIncoming: model.windIncoming,
                    onQuit: onQuit
                )
                .padding(.top, 8)
                Spacer()
            }

            // PERFECT feedback: springy star banner + combo.
            if model.showPerfect {
                VStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Label("PERFECT!", systemImage: "star.fill")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(.yellow)
                        if model.comboStreak > 1 {
                            Text("\(model.comboStreak)× COMBO")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.black.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .stroke(.yellow.opacity(0.6), lineWidth: 2)
                            )
                    )
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                .allowsHitTesting(false)
            }

            // Danger vignette near collapse.
            if model.session.tower.isCritical {
                Color.red.opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if model.pendingRevive != nil {
                ReviveOffer(model: model)
            }
        }
        .animation(.spring(response: 0.35), value: model.showPerfect)
        .animation(.easeInOut, value: model.session.tower.isCritical)
    }
}
