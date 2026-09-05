import GameCore
import XCTest
@testable import GameForge

@MainActor
final class EmberGameModelTests: XCTestCase {
    func testModelStartsBattleAndFinishes() {
        let model = EmberGameModel(profile: PlayerProfile.new())
        XCTAssertNil(model.battle)
        model.startBattle()
        XCTAssertNotNil(model.battle)
        // Tick to completion (fast-forward).
        for _ in 0..<20_000 where model.battle?.outcome == .ongoing {
            model.tickBattle(0.1)
        }
        model.finishBattle()
        XCTAssertNil(model.battle)
    }

    func testSummonUpdatesProfile() {
        let model = EmberGameModel(profile: PlayerProfile.new())
        model.addGemsForTesting(100_000)
        let before = model.profile.totalSummons
        model.summon(banner: .permanent, count: 1)
        XCTAssertEqual(model.profile.totalSummons, before + 1)
    }

    func testIdleClaimGrantsGold() {
        let model = EmberGameModel(profile: PlayerProfile.new())
        let gold = model.claimIdle(secondsAway: 3600)
        XCTAssertGreaterThanOrEqual(gold, 0)
    }

    func testSaveAndReloadRoundTrip() {
        let model = EmberGameModel(profile: PlayerProfile.new())
        model.renamePlayer("Test Keeper")
        model.save()
        let reloaded = EmberGameModel() // loads from disk
        XCTAssertEqual(reloaded.profile.name, "Test Keeper")
        ProfilePersistence.wipe()
    }

    func testSetSquadValidation() {
        let model = EmberGameModel(profile: PlayerProfile.new())
        let ids = model.profile.ownedHeroes.map(\.definitionID)
        model.setSquad(Array(ids.prefix(3))) // too few — rejected
        XCTAssertEqual(model.profile.squad.count, 5)
        model.setSquad(ids) // all 5 owned — accepted
        XCTAssertEqual(model.profile.squad, ids)
    }

    func testFreeDailySummonOncePerDay() {
        let model = EmberGameModel(profile: PlayerProfile.new())
        XCTAssertTrue(model.freeSummonAvailable)
        XCTAssertTrue(model.freeDailySummon())
        XCTAssertEqual(model.profile.totalSummons, 1)
        XCTAssertFalse(model.freeDailySummon()) // already used today
        XCTAssertEqual(model.profile.totalSummons, 1) // second call pulled nothing
        XCTAssertFalse(model.freeSummonAvailable)
        model.consumeSummonResults()
        XCTAssertNil(model.lastSummonResults)
    }

    func testBuyMarketGearBox() {
        let model = EmberGameModel(profile: PlayerProfile.new())
        model.grantGoldForTesting(100_000)
        let entry = MarketSystem.dailyStock().first { $0.currency == .gold && $0.price > 0 && $0.kind.isGearBox }
        XCTAssertNotNil(entry)
        guard let entry else { return }
        let before = model.profile.gearInventory.count
        XCTAssertTrue(model.buyMarket(entryID: entry.id))
        XCTAssertEqual(model.profile.gearInventory.count, before + 1)
    }

    func testFreeMarketClaimOncePerDay() {
        let model = EmberGameModel(profile: PlayerProfile.new())
        XCTAssertFalse(model.freeMarketClaimedToday())
        XCTAssertTrue(model.buyMarket(entryID: "free-daily"))
        XCTAssertTrue(model.freeMarketClaimedToday())
        XCTAssertFalse(model.buyMarket(entryID: "free-daily"))
    }
}
