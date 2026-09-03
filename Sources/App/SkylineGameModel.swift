import Foundation
import GameCore
import SwiftUI

/// Drives one run: owns the SkylineSession and the TowerScene, bridges
/// SceneKit outcomes into GameCore rules, exposes state for the HUD.
@MainActor
final class SkylineGameModel: ObservableObject {
  @Published private(set) var session: SkylineSession
  @Published private(set) var pendingRevive: CollapseOutcome?
  @Published private(set) var runOver = false
  @Published private(set) var lastSummary: SkylineSession.RunSummary?
  @Published private(set) var windIncoming = false

  /// The scene is owned here; RootView embeds it via TowerSceneView.
  let scene: TowerScene
  private let ads: RewardedAdService
  private var wind: WindSystem
  private var nextGustTick: UInt64 = 0
  private var currentGust: WindSystem.Gust?
  private var tick: UInt64 = 0
  private var settleTimer: Timer?

  var onRunOver: (() -> Void)?

  init(meta: SkylineMeta, startingCoins: Int, ads: RewardedAdService, windSeed: UInt64 = 42) {
    self.ads = ads
    self.scene = TowerScene()
    self.wind = WindSystem(seed: windSeed)
    session = SkylineSession(meta: meta, startingCoins: startingCoins)
    wireSceneCallbacks()
    scheduleNextGust()
    spawnNextDistrict()
  }

  private func wireSceneCallbacks() {
    scene.onCollapse = { [weak self] cause in
      self?.handleCollapse(cause)
    }
  }

  // MARK: Placement

  var currentTypeID: String {
    // Cycle through unlocked types for variety instead of always "homes".
    let unlocked = UnlockLadder.unlockedTypes(level: session.meta.level)
    return unlocked[session.placements % unlocked.count].id
  }

  private func spawnNextDistrict() {
    let typeID = currentTypeID
    guard let type = DistrictType.v1Catalog.first(where: { $0.id == typeID }) else { return }
    scene.spawnDistrict(type)
  }

  /// Called every rendered frame by the scene view. Drives the block slide,
  /// physics-feedback checks, and the wind clock. This is the game's pulse —
  /// without it nothing moves (the v24 "nothing happens" bug).
  func frameUpdate() {
    // Camera follows at most once per 30 frames — running an SCNAction
    // every frame piled up animations and froze the camera (v25 bug).
    if tick % 30 == 0 {
      scene.followTowerTop(height: Float(session.tower.districts.count))
    }
    advanceTick()
    // Death by instability: lean at ceiling → structural collapse.
    if !runOver, session.tower.lean >= 0.92, !collapsePending {
      collapsePending = true
      handleCollapse(.leanOverflow)
    }
  }

  /// Guards against double-collapse in the same frame.
  private var collapsePending = false

  /// Drops the hovering district and applies GameCore rules.
  func dropPendingDistrict() {
    collapsePending = false
    guard let gridX = scene.pendingGridX else { return }
    let result = session.placeDistrict(typeID: currentTypeID, at: GridPoint(x: gridX, z: 0), tick: tick)
    if case .placed = result {
      scene.dropCurrentDistrict()
      tick += 1
      // Spawn the next hovering block immediately — the loop continues.
      spawnNextDistrict()
    } else {
      // Illegal placement: the district stays hovering; nudge the slide.
      scene.removePending()
      spawnNextDistrict()
    }
  }

  // MARK: Collapse & revive

  func handleCollapse(_ cause: CollapseCause) {
    scene.playSlowMotion()
    let outcome = session.handleCollapse(cause: cause, tick: tick)
    scene.removeTopDistrict()
    if session.isRunOver {
      runOver = true
      onRunOver?()
    } else {
      pendingRevive = outcome
    }
  }

  func reviveByAd() async {
    let earned = await ads.show(from: nil)
    if earned {
      session.confirmAdRevive()
      scene.stabilize(seconds: 8)
    } else {
      session.abandonRevive()
    }
    pendingRevive = nil
  }

  func reviveByHelper() -> Bool {
    let ok = session.revive()
    if ok {
      scene.stabilize(seconds: 8)
      pendingRevive = nil
    }
    return ok
  }

  func abandonRevive() {
    session.abandonRevive()
    pendingRevive = nil
  }

  // MARK: Wind

  private func scheduleNextGust() {
    let gust = wind.gust(afterTick: tick)
    nextGustTick = gust.startTick
    currentGust = gust
  }

  /// Advances the world one step; called from the render loop.
  func advanceTick() {
    tick += 1
    scene.tick()
    if let gust = currentGust, tick == gust.startTick {
      scene.applyGust(strength: gust.strength, direction: gust.direction)
      windIncoming = false
    } else if tick >= nextGustTick - 5, tick < nextGustTick {
      windIncoming = true
    } else if let gust = currentGust, tick > gust.startTick + gust.durationTicks {
      scheduleNextGust()
    }
  }

  // MARK: Run end

  func endRun(gameCenter: GameCenterService? = nil) -> SkylineSession.RunSummary {
    let summary = session.endRun()
    lastSummary = summary
    if let gameCenter {
      Task { await gameCenter.submitDailyHeight(summary.height) }
    }
    return summary
  }
}
