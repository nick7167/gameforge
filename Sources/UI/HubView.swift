import GameCore
import SceneKit
import SwiftUI

/// World hub: portrait-framed 3D stronghold (tappable buildings) with a top
/// bar, floating idle chest, and bottom tab bar. Tab contents other than the
/// hub are placeholders for later tasks.
struct HubView: View {
  enum Tab: String, CaseIterable {
    case hub = "Hub", heroes = "Heroes", summon = "Summon", market = "Market", more = "More"

    var symbol: String {
      switch self {
      case .hub: "house.fill"
      case .heroes: "person.2.fill"
      case .summon: "sparkles"
      case .market: "cart.fill"
      case .more: "ellipsis.fill"
      }
    }
  }

  @ObservedObject var model: EmberGameModel
  let onStartBattle: () -> Void

  @State private var selectedTab: Tab = .hub
  @State private var hubScene: HubScene? // created once in onAppear
  @State private var toast: String?
  @State private var toastTask: Task<Void, Never>?
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ZStack {
      DS.emberDark.ignoresSafeArea()
      tabContent
      topBar
        .frame(maxHeight: .infinity, alignment: .top)
      if selectedTab == .hub {
        idleChest
          .frame(maxHeight: .infinity, alignment: .bottom)
          .padding(.bottom, 92)
      }
      VStack {
        Spacer()
        tabBar
      }
      .ignoresSafeArea(edges: .bottom)
      if let toast {
        toastCapsule(toast)
      }
    }
    .onAppear {
      if hubScene == nil {
        hubScene = HubScene(squad: squadFigures)
      }
      model.refreshIdleEstimate()
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      model.refreshIdleEstimate()
    }
  }

  /// Squad roster mapped to what the scene needs to draw wandering figures.
  private var squadFigures: [(id: String, name: String, faction: Faction)] {
    model.profile.squad.prefix(5).compactMap { id in
      guard let def = HeroCatalog.hero(id: id) else { return nil }
      return (id: def.id, name: def.name, faction: def.faction)
    }
  }

  // MARK: - Tab content

  @ViewBuilder
  private var tabContent: some View {
    switch selectedTab {
    case .hub:
      hubLayer
    case .heroes:
      HeroesView(model: model)
    case .summon:
      SummonView(model: model)
    case .market:
      ComingSoonView(title: "Market")
    case .more:
      ComingSoonView(title: "More")
    }
  }

  private var hubLayer: some View {
    Group {
      if let hubScene {
        SceneViewHost(
          scene: hubScene.scene,
          scnView: Binding(
            get: { HubSceneViewStore.view },
            set: { HubSceneViewStore.view = $0 }))
          .overlay(spatialTap)
      }
    }
  }

  /// SpatialTapGesture hands over the tap location so the scene can hit-test.
  private var spatialTap: some View {
    Color.clear
      .contentShape(Rectangle())
      .gesture(
        SpatialTapGesture()
          .onEnded { value in
            handleTap(at: value.location)
          })
  }

  private func handleTap(at point: CGPoint) {
    // The gesture reports coordinates in the overlay's space, which matches
    // the SCNView frame here; hubLayer fills the same rect.
    guard let hubScene, let scnView = HubSceneViewStore.view else { return }
    guard let action = hubScene.handleTap(at: point, in: scnView) else { return }
    switch action {
    case .battle:
      onStartBattle()
    case .summon:
      selectedTab = .summon
    case .heroes:
      selectedTab = .heroes
    case .shop:
      showToast("Premium shop coming in Task 8")
    case .locked(let label):
      showToast("\(label) — coming soon!")
    }
  }

  // MARK: - Top bar

  private var topBar: some View {
    HStack(spacing: 10) {
      avatar
      VStack(alignment: .leading, spacing: 0) {
        Text(model.profile.name)
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundColor(DS.textPrimary)
          .lineLimit(1)
        Text("Lv \(model.profile.accountLevel)")
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundColor(DS.textSecondary)
      }
      Spacer()
      CurrencyChip(icon: "💎", value: model.profile.wallet.balance(of: .gems))
      CurrencyChip(icon: "🪙", value: model.profile.wallet.balance(of: .gold))
      Button {
        showToast("Settings coming in Task 9")
      } label: {
        Image(systemName: "gearshape.fill")
          .font(.system(size: 18))
          .foregroundColor(DS.textSecondary)
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 6)
  }

  private var avatar: some View {
    ZStack {
      Circle().fill(
        LinearGradient(colors: [DS.goldLight, DS.goldDeep], startPoint: .top, endPoint: .bottom))
      Text(String(model.profile.name.first.map(String.init) ?? "?"))
        .font(.system(size: 17, weight: .black, design: .rounded))
        .foregroundColor(DS.emberDark)
    }
    .frame(width: 38, height: 38)
    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
  }

  // MARK: - Idle chest

  private var idleChest: some View {
    Group {
      if model.idleGoldAvailable > 0 {
        Button {
          let claimed = model.claimIdle()
          showToast("+\(claimed.formatted()) gold claimed!")
        } label: {
          OrnatePanel {
            HStack(spacing: 8) {
              Text("🎁").font(.system(size: 20))
              Text(model.idleGoldAvailable.formatted())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(DS.textPrimary)
            }
          }
        }
      }
    }
  }

  // MARK: - Tab bar

  private var tabBar: some View {
    HStack(spacing: 0) {
      ForEach(Tab.allCases, id: \.self) { tab in
        tabButton(tab)
      }
    }
    .padding(.vertical, 8)
    .background(
      VStack(spacing: 0) {
        Rectangle().fill(DS.goldDeep.opacity(0.8)).frame(height: 1.5)
        Rectangle().fill(Color.black.opacity(0.85))
      }
      .ignoresSafeArea(edges: .bottom))
  }

  private func tabButton(_ tab: Tab) -> some View {
    let selected = selectedTab == tab
    return Button {
      selectedTab = tab
    } label: {
      VStack(spacing: 3) {
        Image(systemName: tab.symbol)
          .font(.system(size: 19, weight: .semibold))
        Text(tab.rawValue)
          .font(.system(size: 10, weight: .bold, design: .rounded))
      }
      .foregroundColor(selected ? DS.goldLight : Color(white: 0.55))
      .frame(maxWidth: .infinity)
    }
  }

  // MARK: - Toast

  private func toastCapsule(_ message: String) -> some View {
    VStack {
      Spacer()
      Text(message)
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundColor(DS.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.8)))
        .overlay(Capsule().strokeBorder(DS.goldDeep.opacity(0.7), lineWidth: 1))
        .padding(.bottom, 100)
    }
    .allowsHitTesting(false)
  }

  private func showToast(_ message: String) {
    toastTask?.cancel()
    toast = message
    toastTask = Task { @MainActor in
      try? Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      toast = nil
    }
  }
}

/// Shared handle on the hub's SCNView so the gesture overlay can hit-test.
/// SceneKit views are main-thread only; this is only touched from the MainActor.
@MainActor
enum HubSceneViewStore {
  static weak var view: SCNView?
}

/// Centered placeholder for tabs filled in by later tasks.
private struct ComingSoonView: View {
  let title: String

  var body: some View {
    OrnatePanel {
      VStack(spacing: 6) {
        Text(title)
          .font(.system(size: 20, weight: .black, design: .rounded))
          .foregroundColor(DS.textPrimary)
        Text("Coming soon")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(DS.textSecondary)
      }
      .frame(minWidth: 200)
    }
  }
}
