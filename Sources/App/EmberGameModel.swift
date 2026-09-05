import Combine
import Foundation
import GameCore

/// The app-side game facade. Owns the EmberSession, republishes state,
/// and drives the battle tick loop. Views observe this; they never touch
/// GameCore types directly for state mutation.
@MainActor
final class EmberGameModel: ObservableObject {
  @Published private(set) var profile: PlayerProfile
  @Published private(set) var battle: BattleEngine?
  @Published private(set) var lastReward: BattleReward?
  @Published private(set) var lastSummonResults: [GachaEngine.PullResult]?
  @Published private(set) var idleGoldAvailable = 0

  private var session: EmberSession
  private var tickTimer: Timer?
  /// Battle speed (1–4). The timer still fires at 30 Hz; the dt is scaled.
  private var tickMultiplier = 1

  var currentStage: StageID { session.currentStage }

  init(profile: PlayerProfile? = nil) {
    let loaded = profile ?? ProfilePersistence.load() ?? PlayerProfile.new()
    session = EmberSession(profile: loaded, rngSeed: UInt64(Date().timeIntervalSince1970))
    self.profile = loaded
    refreshIdleEstimate()
  }

  // MARK: - Battle

  func startBattle() {
    guard battle == nil else { return }
    battle = session.startBattle()
    startTicking()
  }

  func tickBattle(_ dt: Double) {
    guard battle != nil else { return }
    session.tickBattle(dt)
    battle = session.battle
    if battle?.outcome != .ongoing { stopTicking() }
  }

  func fireUltimate(heroID: String) {
    session.fireUltimate(heroID: heroID)
    battle = session.battle
  }

  func finishBattle() {
    lastReward = session.finishBattle()
    battle = session.battle
    syncProfile()
    save()
  }

  private func startTicking() {
    stopTicking()
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.tickBattle(1.0 / 30.0 * Double(self?.tickMultiplier ?? 1))
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    tickTimer = timer
  }

  private func stopTicking() {
    tickTimer?.invalidate()
    tickTimer = nil
  }

  /// Set battle speed (clamped to 1...4). Applied as a dt scale in the tick loop.
  func setSpeed(_ s: Int) {
    tickMultiplier = max(1, min(4, s))
  }

  // MARK: - Meta actions

  func summon(banner: GachaEngine.BannerKind, count: Int) {
    lastSummonResults = session.summon(banner: banner, count: count)
    syncProfile()
    save()
  }

  func levelUpHero(heroID: String) {
    _ = session.levelUpHero(heroID: heroID)
    syncProfile()
    save()
  }

  func equipGear(heroID: String, item: GearItem, slot: GearSlot) {
    _ = session.equipGear(heroID: heroID, item: item, slot: slot)
    syncProfile()
    save()
  }

  func enhanceGear(heroID: String, slot: GearSlot) {
    _ = session.enhanceGear(heroID: heroID, slot: slot)
    syncProfile()
    save()
  }

  @discardableResult
  func claimIdle(secondsAway: Double? = nil) -> Int {
    let gold = session.claimIdle(secondsAway: secondsAway)
    syncProfile()
    save()
    return gold
  }

  func refreshIdleEstimate() {
    // Estimate what's available now without claiming.
    if let last = profile.lastIdleClaim {
      let elapsed = Date().timeIntervalSince(last)
      idleGoldAvailable = IdleIncome.earnings(bestStage: profile.bestStage, secondsAway: elapsed).gold
    } else {
      idleGoldAvailable = 0
    }
  }

  func renamePlayer(_ name: String) {
    session.renamePlayer(name)
    syncProfile()
    save()
  }

  /// Test hook: grant gems without a purchase.
  func addGemsForTesting(_ amount: Int) {
    session.grantGems(amount)
    syncProfile()
  }

  private func syncProfile() {
    profile = session.profile
  }

  func save() {
    ProfilePersistence.save(profile)
  }
}
