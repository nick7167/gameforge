import GameCore
import SceneKit
import SwiftUI
import UIKit

/// SwiftUI host for the SceneKit battle stage (spec §10). The SCNView renders
/// continuously; this layer owns only HUD chrome and event-driven overlays.
/// All gameplay state stays in `EmberGameModel` / GameCore.
struct BattleView: View {
  // MARK: - Overlay models

  struct DamageNumber: Identifiable {
    let id = UUID()
    let unitID: String
    let text: String
    let kind: BattleScene.DamageKind
    let createdAt: Date
    let offset: CGPoint
  }

  struct UltBannerData {
    let heroName: String
    let skillName: String
    let id = UUID()
  }

  @ObservedObject var model: EmberGameModel
  @StateObject private var coordinator = BattleCoordinator()
  @State private var autoUlt = false
  @State private var speed = 1

  var body: some View {
    ZStack {
      if let battle = model.battle {
        sceneLayer
        damageOverlay
        hud(battle)
        ultBannerOverlay
        if battle.outcome != .ongoing {
          resultPopup(battle)
        }
      }
    }
    .ignoresSafeArea()
    .onAppear {
      setupSceneIfNeeded()
      syncScene()
    }
    .onChange(of: model.battle?.elapsed) { old, elapsed in
      handleTick(from: old, to: elapsed)
    }
  }

  // MARK: - Tick plumbing

  private func handleTick(from old: Double?, to elapsed: Double?) {
    guard let elapsed, model.battle != nil else {
      // Battle went away (finished) — drop scene and overlays.
      coordinator.reset()
      return
    }
    // A decreasing or previously absent elapsed marks a brand-new battle.
    if old == nil || elapsed < (old ?? 0) {
      coordinator.reset()
    }
    setupSceneIfNeeded()
    syncScene()
    if autoUlt {
      fireChargedUlts()
    }
  }

  private func setupSceneIfNeeded() {
    guard let engine = model.battle, coordinator.battleScene == nil else { return }
    coordinator.battleScene = BattleScene(engine: engine)
  }

  private func syncScene() {
    guard let scene = coordinator.battleScene, let engine = model.battle else { return }
    scene.sync(engine: engine, events: coordinator.makeEvents())
  }

  private func fireChargedUlts() {
    guard let battle = model.battle else { return }
    for hero in battle.heroes where hero.isAlive && hero.ultCharge >= 1 {
      _ = model.fireUltimate(heroID: hero.id)
    }
  }

  private func fireUltimate(heroID: String) {
    if let result = model.fireUltimate(heroID: heroID) {
      coordinator.battleScene?.playUltimate(heroID: heroID, result: result)
      if let hero = model.battle?.heroes.first(where: { $0.id == heroID }) {
        coordinator.showUltBanner(heroName: hero.def.name, skillName: hero.def.ultimate.name)
      }
    }
  }

  // MARK: - Scene

  private var sceneLayer: some View {
    Group {
      if let scene = coordinator.battleScene {
        SceneViewHost(
          scene: scene.scene,
          scnView: Binding(
            get: { coordinator.scnView },
            set: { coordinator.scnView = $0 }))
      }
    }
  }

  // MARK: - HUD

  private func hud(_ battle: BattleEngine) -> some View {
    GeometryReader { geo in
      VStack {
        HStack(alignment: .top) {
          stageBadge
          Spacer()
          if battle.isBoss {
            bossBar(battle)
              .frame(maxWidth: 230)
              .padding(.top, 6)
          }
          Spacer()
          autoToggle
        }
        Spacer()
        HStack(alignment: .bottom) {
          speedChip
          Spacer()
          ultRow(battle)
        }
      }
      .padding(.horizontal, 14)
      .padding(.top, geo.safeAreaInsets.top + 8)
      .padding(.bottom, geo.safeAreaInsets.bottom + 10)
    }
  }

  private var stageBadge: some View {
    let stage = model.currentStage
    return OrnatePanel {
      VStack(spacing: 2) {
        Text(stage.display)
          .font(.system(size: 17, weight: .heavy, design: .rounded))
          .foregroundColor(DS.textPrimary)
        Text(StageProgression.biome(for: stage.chapter).displayName)
          .font(.caption2)
          .foregroundColor(DS.textSecondary)
      }
    }
    .padding(4)
  }

  private var autoToggle: some View {
    let locked = model.profile.accountLevel < 5
    return Button {
      guard !locked else { return }
      autoUlt.toggle()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: locked ? "lock.fill" : "bolt.fill")
        Text("AUTO")
      }
      .font(.system(size: 12, weight: .heavy, design: .rounded))
      .foregroundColor(
        locked ? DS.textSecondary.opacity(0.5) : (autoUlt ? DS.emberDark : DS.textPrimary))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        Capsule().fill(locked ? Color.black.opacity(0.3) : (autoUlt ? DS.goldLight : Color.black.opacity(0.45))))
      .overlay(Capsule().strokeBorder(DS.goldDeep.opacity(0.7), lineWidth: 1))
    }
    .disabled(locked)
  }

  private func bossBar(_ battle: BattleEngine) -> some View {
    let boss = battle.enemies.first { $0.isBoss }
    let ratio = boss.map { max(0, min(1, $0.hp / $0.maxHP)) } ?? 0
    return VStack(spacing: 4) {
      Text(boss?.def.name.uppercased() ?? "BOSS")
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .tracking(2)
        .foregroundColor(DS.textPrimary)
        .shadow(color: .black, radius: 2)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.black.opacity(0.55))
          Capsule()
            .fill(
              LinearGradient(
                colors: [Color(red: 1.0, green: 0.32, blue: 0.26), Color(red: 0.72, green: 0.08, blue: 0.10)],
                startPoint: .leading, endPoint: .trailing))
            .frame(width: geo.size.width * CGFloat(ratio))
        }
      }
      .frame(height: 12)
      HStack(spacing: 5) {
        ForEach(1...2, id: \.self) { phase in
          Circle()
            .fill(phase <= battle.phase ? DS.goldLight : Color.white.opacity(0.25))
            .frame(width: 7, height: 7)
        }
      }
    }
  }

  private var speedChip: some View {
    Button {
      speed = speed == 1 ? 2 : (speed == 2 ? 4 : 1)
      model.setSpeed(speed)
    } label: {
      Text("\(speed)×")
        .font(.system(size: 15, weight: .heavy, design: .rounded))
        .foregroundColor(DS.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(DS.goldDeep.opacity(0.7), lineWidth: 1))
    }
  }

  private func ultRow(_ battle: BattleEngine) -> some View {
    HStack(spacing: 10) {
      ForEach(battle.heroes) { hero in
        UltPortrait(hero: hero) { heroID in
          fireUltimate(heroID: heroID)
        }
      }
    }
  }

  // MARK: - Damage numbers

  private var damageOverlay: some View {
    ZStack {
      ForEach(coordinator.damageNumbers) { number in
        damageNumber(number)
      }
    }
    .allowsHitTesting(false)
  }

  /// Floats up 60pt and fades over 1.1s; progress is derived from the tick
  /// cadence so it stays in sync with the 30 Hz re-renders.
  private func damageNumber(_ number: DamageNumber) -> some View {
    Group {
      if let scnView = coordinator.scnView,
        let scene = coordinator.battleScene,
        let origin = scene.unitScreenPosition(unitID: number.unitID, in: scnView) {
        let progress = min(1, max(0, Date().timeIntervalSince(number.createdAt) / 1.1))
        DamageNumberStyle.outlinedText(number.text, kind: styleKind(number.kind))
          .position(
            x: origin.x + number.offset.x,
            y: origin.y + number.offset.y - 60 * progress)
          .opacity(1 - progress)
      }
    }
  }

  private func styleKind(_ kind: BattleScene.DamageKind) -> DamageNumberStyle.Kind {
    switch kind {
    case .normal: return .normal
    case .crit: return .crit
    case .ult: return .ult
    case .heal: return .heal
    }
  }

  // MARK: - Ult banner

  private var ultBannerOverlay: some View {
    ZStack {
      if let banner = coordinator.ultBanner {
        VStack(spacing: 6) {
          Text(banner.heroName)
            .font(.system(size: 42, weight: .black, design: .serif))
            .foregroundColor(DS.goldLight)
            .shadow(color: DS.goldMid.opacity(0.9), radius: 12)
          Text(banner.skillName.uppercased())
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .tracking(6)
            .foregroundColor(DS.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 130)
        .transition(.scale(scale: 1.5).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: 0.25), value: coordinator.ultBanner?.id)
    .allowsHitTesting(false)
  }

  // MARK: - Result popup

  private func resultPopup(_ battle: BattleEngine) -> some View {
    let victory = battle.outcome == .victory
    return ZStack {
      Color.black.opacity(0.78)
      VStack(spacing: 22) {
        Text(victory ? "VICTORY!" : "DEFEAT")
          .font(.system(size: 46, weight: .black, design: .serif))
          .foregroundStyle(
            victory
              ? AnyShapeStyle(LinearGradient(colors: [DS.goldLight, DS.goldDeep], startPoint: .top, endPoint: .bottom))
              : AnyShapeStyle(Color(red: 0.95, green: 0.30, blue: 0.28)))
        if victory, let reward = model.lastReward {
          rewardRows(reward)
        }
        GoldButton(title: victory ? "NEXT" : "RETRY", style: .gold) {
          model.finishBattle()
          if !victory {
            model.startBattle()
          }
        }
      }
      .padding(34)
    }
  }

  private func rewardRows(_ reward: BattleReward) -> some View {
    VStack(spacing: 10) {
      CurrencyChip(icon: "🪙", value: reward.gold)
      ForEach(reward.gearDrops) { drop in
        HStack(spacing: 8) {
          Image(systemName: "shield.lefthalf.filled")
          Text(drop.slot.rawValue.capitalized)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(DS.rarityColor(drop.rarity))
        }
      }
    }
  }
}

// MARK: - Ult portrait

/// One squad member's ultimate button: faction-gradient circle, dark sweep for
/// remaining charge, pulsing gold ring when charged, dimmed when dead.
private struct UltPortrait: View {
  let hero: BattleEngine.Unit
  let onFire: (String) -> Void

  @State private var pulsing = false

  private var charged: Bool { hero.ultCharge >= 1 && hero.isAlive }

  var body: some View {
    Button {
      guard charged else { return }
      onFire(hero.id)
    } label: {
      ZStack {
        Circle()
          .fill(
            LinearGradient(
              colors: [DS.factionColor(hero.def.faction).opacity(0.9), DS.panelDark],
              startPoint: .top, endPoint: .bottom))
        chargeSweep
        Text(String(hero.def.name.prefix(1)).uppercased())
          .font(.system(size: 22, weight: .black, design: .rounded))
          .foregroundColor(.white)
        ring
      }
      .frame(width: 56, height: 56)
      .opacity(hero.isAlive ? 1 : 0.35)
    }
    .disabled(!charged)
    .scaleEffect(pulsing && charged ? 1.1 : 1)
    .onChange(of: hero.ultCharge >= 1) { _, isCharged in
      guard isCharged else { return }
      withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
        pulsing = true
      }
    }
  }

  /// Dark sweep rising from the bottom: its uncovered height shrinks as
  /// ultCharge fills.
  private var chargeSweep: some View {
    GeometryReader { geo in
      VStack(spacing: 0) {
        Spacer(minLength: 0)
        Rectangle()
          .fill(Color.black.opacity(0.55))
          .frame(height: geo.size.height * CGFloat(1 - min(1, hero.ultCharge)))
      }
    }
    .clipShape(Circle())
  }

  private var ring: some View {
    Circle()
      .strokeBorder(charged ? DS.goldLight : DS.goldDeep.opacity(0.5), lineWidth: 2)
      .opacity(pulsing && charged ? 0.7 : 1)
      .shadow(color: charged ? DS.goldMid.opacity(0.9) : .clear, radius: 5)
  }
}

// MARK: - Scene host

/// `UIViewRepresentable` wrapper configuring the SCNView for the battle stage.
/// The SCNView reference is handed back through the binding so HUD overlays can
/// project world positions to screen points.
struct SceneViewHost: UIViewRepresentable {
  let scene: SCNScene
  let scnView: Binding<SCNView?>

  func makeUIView(context: Context) -> SCNView {
    let view = SCNView()
    view.scene = scene
    view.antialiasingMode = .multisampling4X
    view.preferredFramesPerSecond = 60
    view.rendersContinuously = true
    view.backgroundColor = .clear
    view.isJitteringEnabled = true
    view.allowsCameraControl = false
    scnView.wrappedValue = view
    return view
  }

  func updateUIView(_ uiView: SCNView, context: Context) {
    if uiView.scene !== scene {
      uiView.scene = scene
    }
    // Re-register after coordinator resets; scnView is a plain var, so this
    // never publishes during a view update.
    scnView.wrappedValue = uiView
  }
}

// MARK: - Coordinator

/// Holds SceneKit/HUD state that must survive SwiftUI value semantics and owns
/// the battle event closures. MainActor-isolated; SCNView is main-thread only.
@MainActor
final class BattleCoordinator: ObservableObject {
  @Published var damageNumbers: [BattleView.DamageNumber] = []
  @Published var ultBanner: BattleView.UltBannerData?
  var battleScene: BattleScene?
  var scnView: SCNView?

  func reset() {
    battleScene = nil
    scnView = nil
    damageNumbers.removeAll()
    ultBanner = nil
  }

  func makeEvents() -> BattleScene.BattleEvents {
    BattleScene.BattleEvents(
      onDamageNumber: { [weak self] unitID, text, kind in
        self?.addDamageNumber(unitID: unitID, text: text, kind: kind)
      },
      onUnitDied: { _ in },
      onUltimateCharged: { _ in
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      },
      onUltFlash: nil)
  }

  private func addDamageNumber(unitID: String, text: String, kind: BattleScene.DamageKind) {
    let now = Date()
    // Evict numbers past their 1.1s lifetime so the overlay stays bounded.
    damageNumbers.removeAll { now.timeIntervalSince($0.createdAt) > 1.1 }
    let offset = CGPoint(x: CGFloat.random(in: -28...28), y: CGFloat.random(in: -8...8))
    damageNumbers.append(
      BattleView.DamageNumber(unitID: unitID, text: text, kind: kind, createdAt: now, offset: offset))
  }

  func showUltBanner(heroName: String, skillName: String) {
    let banner = BattleView.UltBannerData(heroName: heroName, skillName: skillName)
    ultBanner = banner
    let id = banner.id
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_300_000_000)
      if self.ultBanner?.id == id {
        self.ultBanner = nil
      }
    }
  }
}
