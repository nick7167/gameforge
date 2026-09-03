import GameCore
import SwiftUI

enum AppPhase: Equatable {
    case menu, playing, shop, gameOver
}

/// Launch-argument routing for UI-test screenshots in CI.
enum UITestConfig {
    static var skipToGameplay: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestSkipToGameplay")
    }
    static var skipToShop: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestSkipToShop")
    }
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
            // Coin grants flow into the active game model's economy.
        }
        // UI-test routing (screenshots in CI): launch args skip menus so the
        // pipeline can capture gameplay deterministically.
        if UITestConfig.skipToGameplay {
            let meta = SkylinePersistence.load() ?? SkylineMeta()
            _meta = State(initialValue: meta)
            let model = SkylineGameModel(meta: meta, startingCoins: 0, ads: NoOpAdService())
            _gameModel = State(initialValue: model)
            _phase = State(initialValue: .playing)
        } else if UITestConfig.skipToShop {
            _phase = State(initialValue: .shop)
        }
    }

    var body: some View {
        switch phase {
        case .menu: menuScreen
        case .playing: gameplayScreen
        case .shop: ShopScreen(purchases: purchases) { phase = .menu }
        case .gameOver: gameOverScreen
        }
    }

    // MARK: Screens

    private var menuScreen: some View {
        StartScreen(
            level: meta.level,
            coins: coins,
            bestHeight: bestHeight,
            onStart: { startRun() },
            onShop: { phase = .shop }
        )
    }

    private var gameplayScreen: some View {
        Group {
            if let model = gameModel {
                ZStack {
                    // Warm sky gradient behind the 3D scene.
                    LinearGradient(
                        colors: [Color(red: 0.23, green: 0.16, blue: 0.28),
                                 Color(red: 0.85, green: 0.66, blue: 0.48),
                                 Color(red: 0.98, green: 0.88, blue: 0.70)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    TowerSceneView(scene: model.scene, onFrame: {
                        model.frameUpdate()
                    })
                    .ignoresSafeArea()
                    VStack {
                        GameHUD(
                            lean: model.session.tower.lean,
                            coins: model.session.economy.coins,
                            height: model.session.tower.districts.count * 10,
                            windIncoming: model.windIncoming,
                            onQuit: { endRunAndExit() }
                        )
                        .padding(.top, 8)
                        Spacer()
                    }
                    // PERFECT feedback: brief center flash + combo count.
                    if model.showPerfect {
                        VStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Text("PERFECT!")
                                    .font(.title2.weight(.heavy))
                                    .foregroundStyle(.yellow)
                                if model.comboStreak > 1 {
                                    Text("×\(model.comboStreak) combo")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(20)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 20))
                            Spacer()
                        }
                        .allowsHitTesting(false)
                        .transition(.scale.combined(with: .opacity))
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
                .onTapGesture {
                    model.dropPendingDistrict()
                }
            }
        }
    }

    private var gameOverScreen: some View {
        Group {
            if let summary {
                GameOverScreen(
                    summary: summary,
                    onReplay: { startRun() },
                    onMenu: { phase = .menu }
                )
            }
        }
    }

    /// Ends the run early (player quits) and returns to the menu.
    private func endRunAndExit() {
        guard let model = gameModel else { return }
        summary = model.endRun()
        meta = model.session.meta
        SkylinePersistence.save(meta)
        gameModel = nil
        phase = .menu
    }

    /// Coins persist across runs via the economy of the latest session.
    private var coins: Int {
        gameModel?.session.economy.coins ?? 0
    }

    /// Best height reached (each district = 10 m), from the saved meta.
    private var bestHeight: Int {
        meta.savedDistricts.count * 10
    }

    private func startRun() {
        let ads: RewardedAdService = UITestConfig.skipToGameplay ? NoOpAdService() : AdMobService()
        let model = SkylineGameModel(meta: meta, startingCoins: coins, ads: ads)
        model.onRunOver = { [weak model] in
            guard let model else { return }
            let gameCenter = GameCenterService()
            summary = model.endRun(gameCenter: gameCenter)
            meta = model.session.meta
            SkylinePersistence.save(meta)
            phase = .gameOver
        }
        gameModel = model
        phase = .playing
    }

    #Preview {
        RootView()
    }
}
