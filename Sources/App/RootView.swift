import GameCore
import SwiftUI

enum AppPhase: Equatable {
    case menu, playing, shop, gameOver
}

/// Owns app navigation and the long-lived services. All gameplay state
/// lives in `SkylineGameModel`/`SkylineSession`; this view drives and renders.
struct RootView: View {
    @StateObject private var purchases = PurchaseService()
    @State private var phase: AppPhase = .menu
    @State private var gameModel: SkylineGameModel?
    @State private var summary: SkylineSession.RunSummary?
    @State private var meta = SkylinePersistence.load() ?? SkylineMeta()

    init() {
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String
        _purchases = StateObject(wrappedValue: PurchaseService())
        purchases.configure(apiKey: apiKey) { _ in
            // Coin grants flow into the active game model's economy (Task 9 hook).
        }
    }

    var body: some View {
        switch phase {
        case .menu:
            StartScreen(
                level: meta.level,
                coins: coins,
                onStart: { startRun() },
                onShop: { phase = .shop }
            )
        case .playing:
            if let model = gameModel {
                ZStack {
                    TowerSceneView(scene: model.scene)
                        .ignoresSafeArea()
                    VStack {
                        GameHUD(
                            lean: model.session.tower.lean,
                            coins: model.session.economy.coins,
                            height: model.session.tower.districts.count * 10,
                            windIncoming: model.windIncoming
                        )
                        .padding(.top, 8)
                        Spacer()
                    }
                    if model.pendingRevive != nil {
                        ReviveOffer(model: model)
                    }
                }
                .onTapGesture {
                    model.dropPendingDistrict()
                }
            }
        case .shop:
            ShopScreen(purchases: purchases) { phase = .menu }
        case .gameOver:
            if let summary {
                GameOverScreen(
                    summary: summary,
                    onReplay: { startRun() },
                    onMenu: { phase = .menu }
                )
            }
        }
    }

    /// Coins persist across runs via the economy of the latest session.
    private var coins: Int {
        gameModel?.session.economy.coins ?? 0
    }

    private func startRun() {
        let model = SkylineGameModel(meta: meta, startingCoins: coins, ads: NoOpAdService())
        model.onRunOver = { [weak model] in
            guard let model else { return }
            summary = model.endRun()
            meta = model.session.meta
            SkylinePersistence.save(meta)
            phase = .gameOver
        }
        gameModel = model
        phase = .playing
    }
}

#Preview {
    RootView()
}
