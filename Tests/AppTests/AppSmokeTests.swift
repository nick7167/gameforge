import SpriteKit
import SwiftUI
import XCTest

@testable import GameForge

final class AppSmokeTests: XCTestCase {
    func testDemoSceneConfiguresPhysicsAndTitle() {
        let size = CGSize(width: 390, height: 844)
        let scene = DemoScene(size: size)
        XCTAssertEqual(scene.size, size)
        XCTAssertNotEqual(scene.physicsWorld.gravity.dy, 0)
        XCTAssertFalse(scene.children.isEmpty)
    }

    func testDemoSceneScoresOnSpawn() {
        let scene = DemoScene(size: CGSize(width: 390, height: 844))
        var events: [DemoGameEvent] = []
        scene.onEvent = { events.append($0) }
        scene.spawnForTesting()
        XCTAssertEqual(events.count, 1)
        if case .scored(let points) = events.first {
            XCTAssertEqual(points, 1)
        } else {
            XCTFail("Expected scored event")
        }
    }
}
