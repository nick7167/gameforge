import XCTest

@testable import GameForge

final class AppSmokeTests: XCTestCase {
    func testRootViewRenders() {
        // The placeholder shell must build its body without crashing.
        let view = RootView()
        _ = view.body
    }

    func testStartScreenRenders() {
        let view = StartScreen(model: EmberGameModel(profile: PlayerProfile.new()))
        _ = view.body
    }

    func testBattleViewRenders() {
        let model = EmberGameModel(profile: PlayerProfile.new())
        model.startBattle()
        let view = BattleView(model: model)
        _ = view.body
        for _ in 0..<200 where model.battle?.outcome == .ongoing { model.tickBattle(0.1) }
        model.finishBattle()
    }

    func testPlayerProfilePersistenceRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var profile = PlayerProfile.new()
        profile.name = "Ember Knight"
        profile.accountLevel = 7
        let data = try JSONEncoder().encode(profile)
        let url = dir.appendingPathComponent("emberfall-profile.json")
        try data.write(to: url)
        let loaded = try JSONDecoder().decode(PlayerProfile.self, from: Data(contentsOf: url))
        XCTAssertEqual(loaded.name, "Ember Knight")
        XCTAssertEqual(loaded.accountLevel, 7)
    }
}
