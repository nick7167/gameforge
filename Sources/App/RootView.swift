import GameCore
import SwiftUI

enum AppPhase: Equatable {
    case menu, playing, shop, gameOver
}

/// Launch-argument routing for UI-test screenshots/videos in CI.
enum UITestConfig {
    static var skipToGameplay: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestSkipToGameplay")
    }
    static var skipToShop: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestSkipToShop")
    }
    /// Autoplay demo: the game drops blocks by itself — used to record
    /// real gameplay video in CI.
    static var autoplay: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestAutoplay")
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
        // UI-test routing (screenshots/video in CI): launch args skip menus
        // so the pipeline can capture gameplay deterministically.
        if UITestConfig.skipToGameplay || UITestConfig.autoplay {
            let meta = SkylinePersistence.load() ?? SkylineMeta()
            _meta = State(initialValue: meta)
            let model = SkylineGameModel(
                meta: meta, startingCoins: 0,
                ads: NoOpAdService(),
                autoplay: UITestConfig.autoplay
            )
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
                            height: model.session.tower.districts.count * 10,
                            windIncoming: model.windIncoming,
                            onQuit: { endRunAndExit() }
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
