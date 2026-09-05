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

  /// The cost-free daily single summon (spec §6.2). Returns false when already
  /// used today; on success the results land in `lastSummonResults`.
  @discardableResult
  func freeDailySummon() -> Bool {
    guard let results = session.freeDailySummon() else { return false }
    lastSummonResults = results
    syncProfile()
    save()
    return true
  }

  /// Whether today's free daily summon is still available (UI affordance).
  var freeSummonAvailable: Bool {
    session.profile.lastFreeSummonDay != EmberSession.dayIndex(Date())
  }

  /// Clear the summon results after the reveal overlay consumed them.
  func consumeSummonResults() {
    lastSummonResults = nil
  }

  func levelUpHero(heroID: String) {
    _ = session.levelUpHero(heroID: heroID)
    syncProfile()
    save()
  }

  /// Replace the squad. Validates count/uniqueness/ownership; no-op on invalid input.
  func setSquad(_ ids: [String]) {
    guard ids.count == 5, Set(ids).count == 5,
      ids.allSatisfy({ id in profile.ownedHeroes.contains { $0.definitionID == id } })
    else { return }
    session.setSquad(ids)
    profile = session.profile
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
    grantGems(amount)
  }

  /// Grant gems (IAP fulfillment routed through the purchase service).
  func grantGems(_ amount: Int) {
    session.grantGems(amount)
    syncProfile()
  }

  /// Test hook: grant gold without playing.
  func grantGoldForTesting(_ amount: Int) {
    session.grantCurrency(.gold, amount)
    syncProfile()
  }

  // MARK: - Quests

  /// Claim a completed quest's rewards (More tab, Quests screen).
  @discardableResult
  func claimQuest(questID: String) -> Bool {
    let ok = session.claimQuest(questID: questID)
    if ok {
      syncProfile()
      save()
    }
    return ok
  }

  /// Claim every claimable quest in the given list. Returns how many were claimed.
  func claimQuests(_ quests: [QuestDefinition]) -> Int {
    quests.reduce(0) { count, quest in count + (claimQuest(questID: quest.id) ? 1 : 0) }
  }

  // MARK: - Derived stats

  /// Combat power proxy for the whole squad: attack + defense + a tenth of HP
  /// per hero (same formula as the Heroes tab power sort).
  func squadPower() -> Int {
    profile.squad.reduce(0) { sum, id in
      sum + Self.heroPower(profile.ownedHeroes.first { $0.definitionID == id })
    }
  }

  private static func heroPower(_ hero: OwnedHero?) -> Int {
    guard let hero else { return 0 }
    let stats = hero.stats()
    return Int(stats.attack + stats.defense + stats.hp / 10)
  }

  // MARK: - Data reset

  /// Wipe all persisted data and start fresh (Settings: Delete Account).
  func resetAll() {
    ProfilePersistence.wipe()
    let fresh = PlayerProfile.new()
    session = EmberSession(profile: fresh, rngSeed: UInt64(Date().timeIntervalSince1970))
    profile = fresh
    save()
  }

  // MARK: - Market

  /// Buy a Market entry. Returns false when unaffordable / already claimed.
  @discardableResult
  func buyMarket(entryID: String) -> Bool {
    let ok = session.buyMarket(entryID: entryID)
    if ok {
      syncProfile()
      save()
    }
    return ok
  }

  /// Whether today's free Market item is still unclaimed.
  func freeMarketClaimedToday() -> Bool {
    session.freeMarketClaimedToday()
  }

  private func syncProfile() {
    profile = session.profile
  }

  func save() {
    ProfilePersistence.save(profile)
  }
}
