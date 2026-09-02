import SpriteKit
import SwiftUI
import XCTest

import GameCore

@testable import GameForge

final class AppSmokeTests: XCTestCase {
    func testDemoSceneConfiguresPhysicsAndTitle() {
        let size = CGSize(width: 390, height: 844)
        let scene = DemoScene(size: size)
        XCTAssertEqual(scene.size, size)
        XCTAssertNotEqual(scene.physicsWorld.gravity.dy, 0)
        XCTAssertFalse(scene.children.isEmpty)
    }

    func testSkylineMetaCodableRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var meta = SkylineMeta()
        meta.addXP(250)
        let data = try JSONEncoder().encode(meta)
        let url = dir.appendingPathComponent("skyline-meta.json")
        try data.write(to: url)
        let loaded = try JSONDecoder().decode(SkylineMeta.self, from: Data(contentsOf: url))
        XCTAssertEqual(loaded.xp, 250)
        XCTAssertEqual(loaded.level, 3)
    }
}


