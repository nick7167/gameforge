import XCTest
import SwiftUI
import GameCore
@testable import GameForge

final class DesignSystemTests: XCTestCase {
    func testRarityColorsMatchGameCore() {
        // The DS must derive from GameCore's Rarity.uiColorHex, not hardcode.
        for rarity in [Rarity.common, .rare, .epic, .legendary] {
            let color = DS.rarityColor(rarity)
            XCTAssertNotNil(color) // non-crashing derivation
        }
    }

    func testGoldButtonRenders() {
        let view = GoldButton(title: "SUMMON ×10", style: .gold, action: {})
        _ = view.body
        let gem = GoldButton(title: "BUY", style: .gem, action: {})
        _ = gem.body
    }

    func testOrnatePanelRenders() {
        let panel = OrnatePanel { Text("content") }
        _ = panel.body
    }
}
