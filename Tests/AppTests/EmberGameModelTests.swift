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
}
