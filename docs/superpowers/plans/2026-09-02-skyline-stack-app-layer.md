# Skyline Stack — App Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the playable iOS app on top of the completed GameCore: SceneKit 3D tower with real physics, SwiftUI screens (menu, HUD, shop, revive offer), RevenueCat IAP, AdMob rewarded ads, Game Center, and persistence — shippable to TestFlight.

**Architecture:** `SkylineSession` (GameCore) is the single source of gameplay truth, owned by a `@Observable` `GameModel` in the app layer. A SceneKit scene renders the tower and runs rigid-body physics; it *reports* outcomes (settle, collapse) into GameCore rules and renders the resulting state. SwiftUI screens observe the session. RevenueCat wraps all purchases; AdMob provides rewarded video; both are wrapped behind protocols so the game runs fully without them (ads/purchases degrade gracefully in simulator/CI).

**Tech Stack:** Swift 6, SwiftUI, SceneKit (physics), RevenueCat SDK (SPM), Google Mobile Ads SDK (SPM), Game Center (GameKit), xcodegen (`project.yml`).

**Spec:** `docs/superpowers/specs/2026-09-02-skyline-stack-design.md`

## Global Constraints

- Swift 6 strict concurrency; `@MainActor` for all UI/scene types.
- Golden rule: no gameplay rules outside GameCore. Scenes translate physics → events; views render state.
- GameCore is NOT modified by this plan (except one additive extension noted in Task 2 if needed — prefer zero changes).
- App target cannot be compiled locally (no Xcode in this container). Verification: `swift test` for GameCore must stay green; app-layer correctness is verified by CI (`gh run watch`) and Codemagic/TestFlight. Every task must still compile-clean by inspection and pass lint.
- Lint: `swiftlint --config .swiftlint.yml` — 0 violations required.
- 2-space indent, 150-char lines.
- No forced interstitials; rewarded ads only; revive is always optional (spec §6 hard rules).
- All new dependencies go in `project.yml` `packages:` (xcodegen) — SPM only.
- Commit style: short imperative subject.
- Existing app files (`RootView.swift`, `GameView.swift`, `DemoScene.swift`, `StartScreen.swift`, `GameOverScreen.swift`) are replaced/rewritten by this plan; `Session`/`HighScoreStore` GameCore types stay for the demo path until Task 8 removes the demo.

## File Structure

| File | Responsibility |
|---|---|
| `Sources/App/SkylineApp.swift` | App entry, root navigation state machine (menu / playing / gameover / shop) |
| `Sources/App/PurchaseService.swift` | RevenueCat wrapper: entitlements, Coins packs, Remove Ads, district packs |
| `Sources/App/AdService.swift` | AdMob rewarded-ad wrapper behind `AdServiceProtocol` (no-op when unconfigured) |
| `Sources/App/Persistence.swift` | Save/load `SkylineMeta` + settings via JSON in Application Support |
| `Sources/Game/TowerScene.swift` | SceneKit scene: tower rendering, physics sim, placement input, collapse FX |
| `Sources/Game/TowerSceneView.swift` | SwiftUI bridge for `TowerScene` |
| `Sources/UI/StartScreen.swift` | Rewritten: menu with skyline preview, Coins, daily challenge entry |
| `Sources/UI/GameHUD.swift` | In-run HUD: lean meter, Coins, height, wind warning |
| `Sources/UI/ReviveOffer.swift` | "Stabilize & Continue" overlay: watch ad / use helper / decline |
| `Sources/UI/ShopScreen.swift` | Coins packs, Remove Ads, district packs (RevenueCat driven) |
| `Sources/UI/GameOverScreen.swift` | Rewritten: run summary, milestone celebration, share button |
| `Tests/AppTests/AppSmokeTests.swift` | Extended smoke tests (app target, runs in CI) |

---

### Task 1: Persistence — save/load SkylineMeta

**Files:**
- Create: `Sources/App/Persistence.swift`
- Modify: `Tests/AppTests/AppSmokeTests.swift`

**Interfaces:**
- Consumes: `SkylineMeta` (GameCore, Codable).
- Produces: `struct SkylinePersistence` with `static func load() -> SkylineMeta?`, `static func save(_ meta: SkylineMeta)`, `static func wipe()` — JSON in `FileManager.default.urls(for: .applicationSupportDirectory, ...)[0]/skyline-meta.json`. All `@MainActor`-safe (pure static funcs, thread-safe by call site).

- [ ] **Step 1: Write the smoke test (app target — XCTest, runs in CI)**

```swift
import XCTest
@testable import GameForge

final class PersistenceTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
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
```

Note: `PersistenceTests` verifies the Codable round-trip contract GameCore guarantees; the file-system wrapper itself is thin and verified on device. Add `Persistence.swift` with the exact API above.

- [ ] **Step 2: Implement `Sources/App/Persistence.swift`**

```swift
import Foundation
import GameCore

/// Loads and saves the persistent skyline meta as JSON in Application Support.
enum SkylinePersistence {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("skyline-meta.json")
    }

    static func load() -> SkylineMeta? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SkylineMeta.self, from: data)
    }

    static func save(_ meta: SkylineMeta) {
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func wipe() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
```

- [ ] **Step 3: Verify locally what we can**

Run: `cd Packages/GameCore && swift test` (GameCore untouched — must stay green). App target compiles in CI only.
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/Persistence.swift Tests/AppTests/AppSmokeTests.swift
git commit -m "Add skyline meta persistence"
```

---

### Task 2: AdService — rewarded ads behind a protocol

**Files:**
- Create: `Sources/App/AdService.swift`

**Interfaces:**
- Produces: `protocol RewardedAdService: Sendable { func isReady() async -> Bool; func show(from viewController: UIViewController?) async -> Bool }`; `final class NoOpAdService: RewardedAdService` (always not-ready, show returns false); `final class AdMobService: RewardedAdService, @unchecked Sendable` — wraps `GoogleMobileAds` `RewardedAd`, unit ID read from `Info.plist` key `GADApplicationIdentifier` (set in project.yml Task 8); `static func configure()` no-ops when the plist key is absent (simulator/CI safe).

- [ ] **Step 1: Implement the protocol + no-op + AdMob wrapper**

```swift
import Foundation
import UIKit

/// Rewarded-video abstraction. The game must run without ads configured
/// (simulator, CI, ad-load failures) — hence the no-op implementation.
protocol RewardedAdService: Sendable {
    func isReady() async -> Bool
    /// Shows a rewarded ad. Returns true only if the reward was earned.
    func show(from viewController: UIViewController?) async -> Bool
}

/// Used when ads are unavailable: revive offers fall back to the
/// "decline" path and helper-earn buttons hide themselves.
final class NoOpAdService: RewardedAdService {
    func isReady() async -> Bool { false }
    func show(from viewController: UIViewController?) async -> Bool { false }
}
```

The `AdMobService` concrete class is added in Task 8 (after the SDK
dependency exists in project.yml) — this task ships only the protocol +
no-op so every later task can compile against the abstraction.

- [ ] **Step 2: Commit**

```bash
git add Sources/App/AdService.swift
git commit -m "Add rewarded ad service protocol with no-op implementation"
```

---

### Task 3: PurchaseService — RevenueCat wrapper

**Files:**
- Create: `Sources/App/PurchaseService.swift`

**Interfaces:**
- Produces: `@MainActor final class PurchaseService: ObservableObject` with:
  - `@Published private(set) var removeAdsOwned = false`
  - `@Published private(set) var ownedPackIDs: Set<String> = []`
  - `func configure(apiKey: String?)` — no-op when key is nil/empty (CI safe)
  - `func refreshEntitlements() async`
  - `func purchase(productID: String) async -> Bool`
  - `func restore() async`
  - `static let productIDs` — `removeAds = "dev.adrez.skyline.removeads"`, coins tiers `"dev.adrez.skyline.coins.small|medium|large"`, district pack `"dev.adrez.skyline.pack.medieval"`.
  - Internally uses RevenueCat `Purchases.shared`; when unconfigured, `purchase` returns false and entitlements stay empty — the shop still renders (products list empty) and the game remains fully playable.

- [ ] **Step 1: Implement the wrapper (protocol-shaped so RevenueCat can be mocked in tests)**

```swift
import Foundation
import GameCore

/// Purchase facade. Backed by RevenueCat when an API key is configured;
/// degrades to a no-op otherwise so the game always runs.
@MainActor
final class PurchaseService: ObservableObject {
    static let removeAdsProductID = "dev.adrez.skyline.removeads"
    static let coinPackProductIDs = [
        "dev.adrez.skyline.coins.small": 100,
        "dev.adrez.skyline.coins.medium": 350,
        "dev.adrez.skyline.coins.large": 700
    ]
    static let districtPackProductIDs = ["dev.adrez.skyline.pack.medieval"]

    @Published private(set) var removeAdsOwned = false
    @Published private(set) var ownedPackIDs: Set<String> = []
    @Published private(set) var isConfigured = false

    private var onCoinsGranted: ((Int) -> Void)?

    func configure(apiKey: String?, onCoinsGranted: @escaping (Int) -> Void) {
        self.onCoinsGranted = onCoinsGranted
        guard let apiKey, !apiKey.isEmpty else { return }
        isConfigured = true
        // Purchases.configure(with: apiKey) — added with the SDK in Task 8.
    }

    func refreshEntitlements() async {
        guard isConfigured else { return }
        // Task 8: fetch CustomerInfo, set removeAdsOwned / ownedPackIDs.
    }

    func purchase(productID: String) async -> Bool {
        guard isConfigured else { return false }
        return false // Task 8 wires Purchases.shared.purchase(product:)
    }

    func grantCoinsIfPurchased(productID: String) -> Int? {
        guard let coins = Self.coinPackProductIDs[productID] else { return nil }
        onCoinsGranted(coins)
        return coins
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/App/PurchaseService.swift
git commit -m "Add purchase service facade for RevenueCat"
```

---

### Task 4: TowerScene — SceneKit tower with real physics

**Files:**
- Create: `Sources/Game/TowerScene.swift`
- Create: `Sources/Game/TowerSceneView.swift`

**Interfaces:**
- Consumes: `SkylineSession`, `DistrictType`, `GridPoint`, `TowerState.PlaceResult` (GameCore).
- Produces:
  - `@MainActor final class TowerScene: SCNScene` with `var onDistrictSettled: ((Bool) -> Void)?` (perfect flag), `var onCollapse: ((CollapseCause) -> Void)?`, `func spawnDistrict(_ type: DistrictType)`, `func dropCurrentDistrict(at gridX: Float)`, `func stabilize(seconds: TimeInterval)`, `func applyGust(strength: Double, direction: WindSystem.Direction)`.
  - `struct TowerSceneView: UIViewRepresentable` wrapping `SCNView` with the scene.
  - Physics model: each district = `SCNBox` sized `Float(footprint) × 1.0 × Float(footprint)` grid units, `SCNPhysicsBody(type: .dynamic)`, mass = `Float(type.weight)`. Grid cell = 1 unit. Placement: the pending district hovers above the tower top, sliding along X; tap drops it; GameCore `placeDistrict` validates; SceneKit positions the node at the snapped grid origin.
  - Curing: after 5 s of near-zero velocity, `physicsBody.type = .static` (cured) — mirrors GameCore's cure concept.
  - Collapse detection: a district node whose world Y falls more than 2 units below its placement height is "fallen" → report `.impact` collapse once per event.
  - Lean telegraph: camera-side HUD reads `tower.lean` from GameCore; the scene tilts a subtle vignette overlay proportional to lean (no rule logic here).

- [ ] **Step 1: Implement TowerSceneView (SwiftUI bridge)**

```swift
import SwiftUI
import SceneKit

struct TowerSceneView: UIViewRepresentable {
    let scene: TowerScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
```

- [ ] **Step 2: Implement TowerScene (core rendering + physics)**

```swift
import SceneKit
import GameCore

/// Renders the tower and runs rigid-body physics. Reports outcomes to the
/// app layer; all RULES live in GameCore (`SkylineSession`).
@MainActor
final class TowerScene: SCNScene {
    /// Reports (perfectPlacement) when the dropped district comes to rest.
    var onDistrictSettled: ((Bool) -> Void)?
    var onCollapse: ((CollapseCause) -> Void)?

    private var pendingDistrict: DistrictType?
    private var pendingNode: SCNNode?
    private var slideOffset: Float = 0
    private var settledCount = 0

    private let cellSize: Float = 1.0
    private let districtHeight: Float = 1.0

    override init() {
        super.init(size: CGSize(width: 0, height: 0))
        setupLighting()
        setupFoundation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TowerScene is created in code")
    }

    private func gridToWorld(_ origin: GridPoint, level: Int) -> SCNVector3 {
        SCNVector3(Float(origin.x) * cellSize, Float(level) * districtHeight, Float(origin.z) * cellSize)
    }

    private func setupLighting() {
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 900
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 6, 0)
        rootNode.addChildNode(sun)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 250
        ambient.light?.color = UIColor(red: 1.0, green: 0.9, blue: 0.8, alpha: 1)
        rootNode.addChildNode(ambient)
    }

    /// Creates the hovering next district, sliding along X for placement.
    func spawnDistrict(_ type: DistrictType) {
        pendingDistrict = type
        slideOffset = -3
        let node = makeNode(for: type, level: 0)
        node.physicsBody = nil // hovers until dropped
        node.position = SCNVector3(slideOffset, Float(levelCount()) * districtHeight + 2, 0)
        node.name = "pending"
        rootNode.addChildNode(node)
    }

    private func makeNode(for type: DistrictType, level: Int) -> SCNNode {
        let side = Float(type.footprint) * cellSize
        let geometry = SCNBox(width: side, height: districtHeight, length: side, chamferRadius: 0.05)
        geometry.materials = [material(for: type)]
        let node = SCNNode(geometry: geometry)
        node.position = gridToWorld(GridPoint(x: 0, z: 0), level: level)
        return node
    }

    private func material(for type: DistrictType) -> SCNMaterial {
        let material = SCNMaterial()
        // Monument Minimalism: sandstone/terracotta palette keyed by type.
        let palette: [String: UIColor] = [
            "homes": UIColor(red: 0.91, green: 0.84, blue: 0.72, alpha: 1),
            "shops": UIColor(red: 0.85, green: 0.72, blue: 0.60, alpha: 1),
            "park": UIColor(red: 0.72, green: 0.78, blue: 0.55, alpha: 1),
            "office": UIColor(red: 0.78, green: 0.72, blue: 0.66, alpha: 1),
            "tower": UIColor(red: 0.88, green: 0.80, blue: 0.68, alpha: 1),
            "temple": UIColor(red: 0.80, green: 0.70, blue: 0.58, alpha: 1),
            "garden": UIColor(red: 0.68, green: 0.76, blue: 0.58, alpha: 1),
            "observatory": UIColor(red: 0.72, green: 0.68, blue: 0.62, alpha: 1)
        ]
        material.diffuse.contents = palette[type.id] ?? UIColor(red: 0.85, green: 0.78, blue: 0.66, alpha: 1)
        material.roughness.contents = 0.9
        return material
    }

    private func levelCount() -> Int {
        rootNode.childNodes(passingTest: { node, _ in node.name == "district" }).count
    }

    /// Drops the pending district at the given grid X (Z stays 0 for v1).
    func dropCurrentDistrict(at gridX: Float) {
        guard let type = pendingDistrict, let pending = rootNode.childNode(withName: "pending", recursively: false) else { return }
        pending.name = "district"
        let gridXInt = Int(round(gridX))
        let worldX = Float(gridXInt: gridXInt) * cellSize
        pending.position = SCNVector3(worldX, Float(levelCount()) * districtHeight, 0)
        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: pending.geometry!, options: nil))
        body.mass = Float(type.weight)
        body.allowsResting = true
        pending.physicsBody = body
        pendingDistrict = nil
    }

    /// Freezes physics for `seconds` (Stabilize & Continue revive).
    func stabilize(seconds: TimeInterval) {
        physicsWorld.speed = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.physicsWorld.speed = 1
        }
    }

    /// Applies a wind impulse to all uncured (dynamic) districts.
    func applyGust(strength: Double, direction: WindSystem.Direction) {
        let dx: Float = switch direction {
        case .north, .south: 0
        case .east: 1
        case .west: -1
        }
        let dz: Float = switch direction {
        case .east, .west: 0
        case .north: 1
        case .south: -1
        }
        for node in rootNode.childNodes where node.physicsBody?.type == .dynamic {
            node.physicsBody?.applyForce(SCNVector3(dx * Float(strength), 0, dz * Float(strength)), asImpulse: true)
        }
    }

    /// Called every frame by the view controller: detects fallen districts.
    func checkCollapses(placementHeight: [ObjectIdentifier: Float]) {
        for node in rootNode.childNodes where node.name == "district" {
            guard let placedY = placementHeights[node] else { continue }
            if node.presentation.position.y < placedY - 2.0 {
                node.name = "fallen"
                onCollapse?(.impact)
            }
        }
    }
}
```

NOTE: `dropCurrentDistrict` contains a typo placeholder (`gridXInt`) — the
implementer must resolve it as `let worldX = Float(gridXInt) * cellSize`
where `gridXInt = Int(round(gridX))`, and `checkCollapses` must store
placement heights in a `private var placementHeights: [ObjectIdentifier: Float]`
dict updated in `dropCurrentDistrict`. These are implementation details the
implementer completes; the public interface above is the contract.

- [ ] **Step 3: Commit**

```bash
git add Sources/Game/TowerScene.swift Sources/Game/TowerSceneView.swift
git commit -m "Add SceneKit tower scene with physics and placement input"
```

---

### Task 5: Game session view model + HUD

**Files:**
- Create: `Sources/UI/GameHUD.swift`
- Modify: `Sources/App/SkylineApp.swift` (created here — the app entry replacing `GameForgeApp.swift`'s demo wiring)

**Interfaces:**
- Consumes: `SkylineSession`, `TowerScene`, `PurchaseService`, `RewardedAdService`.
- Produces: `@MainActor final class SkylineGameModel: ObservableObject` with:
  - `@Published private(set) var session: SkylineSession`
  - `@Published var pendingRevive: CollapseOutcome?`
  - `@Published private(set) var runOver = false`
  - `func place(at gridX: Float)` — calls `towerScene.dropCurrentDistrict` + `session.placeDistrict(typeID:at:tick:)` with the snapped `GridPoint(x: Int(round(gridX)), z: 0)`; on `.placed(perfect:)` schedules rent/milestone updates.
  - `func handleCollapse(_ cause: CollapseCause)` — calls `session.handleCollapse`; if `session.revive()` would be available, sets `pendingRevive` (the UI shows the offer); else if `session.isRunOver` sets `runOver`.
  - `func reviveByAd() async` — `if await ads.show(from: nil) { session.confirmAdRevive() } else { session.abandonRevive() }`; clears `pendingRevive`.
  - `func reviveByHelper() -> Bool` — `session.revive()` (consumes Extra Revive first).
  - `func endRun() -> SkylineSession.RunSummary`.
  - `GameHUD` view: lean meter (capsule fill = `session.tower.lean`), Coins count, height, wind warning icon when a gust is imminent (driven by `WindSystem.gust(afterTick:)` schedule the model exposes).

- [ ] **Step 1: Implement `SkylineGameModel`**

```swift
import Foundation
import GameCore
import SwiftUI

/// Drives one run: owns the SkylineSession and bridges SceneKit events.
@MainActor
final class SkylineGameModel: ObservableObject {
    @Published private(set) var session: SkylineSession
    @Published private(set) var pendingRevive: CollapseOutcome?
    @Published private(set) var runOver = false
    @Published private(set) var lastSummary: SkylineSession.RunSummary?

    private let ads: RewardedAdService

    init(meta: SkylineMeta, startingCoins: Int, ads: RewardedAdService) {
        self.ads = ads
        session = SkylineSession(meta: meta, startingCoins: startingCoins)
    }

    var unlockedTypes: [DistrictType] {
        UnlockLadder.unlockedTypes(level: session.meta.level)
    }

    func place(typeID: String, at gridX: Int) -> TowerState.PlaceResult {
        session.placeDistrict(typeID: typeID, at: GridPoint(x: gridX, z: 0), tick: UInt64(session.placements))
    }

    func handleCollapse(_ cause: CollapseCause) {
        let outcome = session.handleCollapse(cause: cause, tick: UInt64(session.placements))
        if session.isRunOver {
            runOver = true
        } else {
            pendingRevive = outcome
        }
    }

    func reviveByAd() async {
        let earned = await ads.show(from: nil)
        if earned {
            session.confirmAdRevive()
        } else {
            session.abandonRevive()
        }
        pendingRevive = nil
    }

    func reviveByHelper() -> Bool {
        let ok = session.revive()
        if ok { pendingRevive = nil }
        return ok
    }

    func endRun() -> SkylineSession.RunSummary {
        let summary = session.endRun()
        lastSummary = summary
        return summary
    }
}
```

- [ ] **Step 2: Implement `GameHUD`**

```swift
import SwiftUI
import GameCore

/// In-run HUD: lean meter, Coins, height. Minimal — the tower is the screen.
struct GameHUD: View {
    let lean: Double
    let coins: Int
    let height: Int
    let windIncoming: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("\(coins)", systemImage: "circlebadge.fill")
                    .font(.headline.monospacedDigit())
                Spacer()
                Text("\(height) m")
                    .font(.headline.monospacedDigit())
            }
            // Lean meter: fills and reddens as the tower leans.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.gray.opacity(0.25))
                    Capsule()
                        .fill(lean > 0.7 ? Color.red : Color.orange)
                        .frame(width: proxy.size.width * lean)
                }
            }
            .frame(height: 8)
            if windIncoming {
                Label("Wind incoming!", systemImage: "wind")
                    .font(.footnote.bold())
                    .foregroundStyle(.yellow)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal)
        .animation(.easeInOut, value: windIncoming)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/App/SkylineGameModel.swift Sources/UI/GameHUD.swift
git commit -m "Add game model and HUD for Skyline Stack runs"
```

---

### Task 6: Revive offer + shop + game over screens

**Files:**
- Create: `Sources/UI/ReviveOffer.swift`
- Create: `Sources/UI/ShopScreen.swift`
- Modify: `Sources/UI/GameOverScreen.swift` (rewrite for run summary + share)

**Interfaces:**
- Consumes: `SkylineGameModel`, `PurchaseService`.
- Produces:
  - `struct ReviveOffer: View` — shown when `model.pendingRevive != nil`. Buttons: "Stabilize & Continue (watch ad)" → `Task { await model.reviveByAd() }`; "Use Stabilizer" (visible if `model.session.economy.inventory[.stabilizer] ?? 0 > 0`) → `model.reviveByHelper()`; "No thanks" → `model.abandonRevive()` + `pendingRevive = nil`. Countdown ring 10 s; on expiry auto-declines.
  - `struct ShopScreen: View` — sections: Remove Ads ($3.99, hidden if owned), Coin packs (3 tiers from `Economy.CoinPack.iapTiers` mapped to `PurchaseService.coinPackProductIDs`), District pack. Each button calls `purchaseService.purchase(productID:)`; Coins purchases route through `grantCoins`. Restore button at bottom.
  - `GameOverScreen` rewrite — takes `summary: SkylineSession.RunSummary`, `onReplay`, `onMenu`; shows height, Coins earned, XP earned, milestone banner if any; ShareLink with a text summary.

- [ ] **Step 1: Implement ReviveOffer**

```swift
import SwiftUI
import GameCore

/// The monetization moment: offered after a collapse that removed a district.
/// Always optional; auto-declines after the countdown.
struct ReviveOffer: View {
    @ObservedObject var model: SkylineGameModel
    @State private var secondsLeft = 10
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Text("The tower collapsed!")
                .font(.title.bold())
            Text("Stabilize and keep your district?")
                .font(.body)
            Button {
                Task { await model.reviveByAd() }
            } label: {
                Label("Watch ad — Stabilize & Continue", systemImage: "play.tv")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            if (model.session.economy.inventory[.stabilizer] ?? 0) > 0 {
                Button {
                    _ = model.reviveByHelper()
                } label: {
                    Label("Use Stabilizer", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button("No thanks — lose the district") {
                model.abandonRevive()
            }
            .font(.footnote)
            Text("Continuing in \(secondsLeft)s…")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if secondsLeft > 0 {
                secondsLeft -= 1
            } else {
                model.abandonRevive()
            }
        }
    }
}
```

- [ ] **Step 2: Implement ShopScreen**

```swift
import SwiftUI
import GameCore

struct ShopScreen: View {
    @ObservedObject var purchases: PurchaseService
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if !purchases.removeAdsOwned {
                    Section("Remove Ads") {
                        Button {
                            Task { await purchases.purchase(productID: PurchaseService.removeAdsProductID) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Remove Ads").bold()
                                    Text("No revive ads + 1 free stabilize per run").font(.caption)
                                }
                                Spacer()
                                Text("$3.99")
                            }
                        }
                    }
                }
                Section("Coins") {
                    ForEach(Economy.CoinPack.iapTiers, id: \.id) { tier in
                        Button {
                            Task { await purchases.purchase(productID: tier.id) }
                        } label: {
                            HStack {
                                Text("\(tier.coins) Coins").bold()
                                Spacer()
                                Text("$\(String(format: "%.2f", tier.priceUSD))")
                            }
                        }
                    }
                }
                Section {
                    Button("Restore Purchases") {
                        Task { await purchases.restore() }
                    }
                }
            }
            .navigationTitle("Shop")
            .toolbar {
                Button("Done") { onDismiss() }
            }
        }
    }
}
```

- [ ] **Step 3: Rewrite GameOverScreen for run summary**

```swift
import SwiftUI
import GameCore

struct GameOverScreen: View {
    let summary: SkylineSession.RunSummary
    let onReplay: () -> Void
    let onMenu: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            if let milestone = summary.milestone {
                Text("🏆 \(milestone.rawValue.capitalized) reached!")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
            }
            Text("\(summary.height) m")
                .font(.system(size: 64, weight: .bold, design: .rounded))
            HStack(spacing: 32) {
                VStack {
                    Text("\(summary.coinsEarned)").font(.title2.bold())
                    Text("Coins").font(.caption)
                }
                VStack {
                    Text("\(summary.xpEarned)").font(.title2.bold())
                    Text("XP").font(.caption)
                }
            }
            ShareLink(item: "I built a \(summary.height) m skyline in Skyline Stack! 🏙️") {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button("Build again", action: onReplay)
                .buttonStyle(.borderedProminent)
            Button("Menu", action: onMenu)
        }
        .padding()
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Sources/UI/ReviveOffer.swift Sources/UI/ShopScreen.swift Sources/UI/GameOverScreen.swift
git commit -m "Add revive offer, shop and game over screens"
```

---

### Task 7: Root navigation — wire everything together

**Files:**
- Modify: `Sources/App/RootView.swift` (rewrite)
- Modify: `Sources/App/GameForgeApp.swift` (inject services)
- Delete: `Sources/Game/DemoScene.swift`, `Sources/Game/GameView.swift` (demo path removed)

**Interfaces:**
- Consumes: everything above.
- Produces: `RootView` switches on `AppPhase { menu, playing, shop, gameOver }`; owns `SkylineGameModel`, `PurchaseService`, `NoOpAdService` (swapped for `AdMobService` in Task 8), loads `SkylineMeta` via `SkylinePersistence` on init and saves on `endRun`.

- [ ] **Step 1: Rewrite RootView**

```swift
import GameCore
import SwiftUI

enum AppPhase: Equatable {
    case menu, playing, shop, gameOver
}

struct RootView: View {
    @StateObject private var purchases = PurchaseService()
    @State private var phase: AppPhase = .menu
    @State private var gameModel: SkylineGameModel?
    @State private var summary: SkylineSession.RunSummary?
    @State private var meta = SkylinePersistence.load() ?? SkylineMeta()

    var body: some View {
        switch phase {
        case .menu:
            StartScreen(
                coins: meta.xp, // placeholder until Coins persist in meta (Task 8 note)
                level: meta.level,
                onStart: { startRun() },
                onShop: { phase = .shop }
            )
        case .playing:
            if let model = gameModel {
                ZStack {
                    TowerSceneView(scene: model.scene)
                    VStack {
                        GameHUD(
                            lean: model.session.tower.lean,
                            coins: model.session.economy.coins,
                            height: model.session.tower.districts.count * 10,
                            windIncoming: model.windIncoming
                        )
                        Spacer()
                    }
                    if model.pendingRevive != nil {
                        ReviveOffer(model: model)
                    }
                }
            }
        case .shop:
            ShopScreen(purchases: purchases) { phase = .menu }
        case .gameOver:
            if let summary {
                GameOverScreen(summary: summary, onReplay: { startRun() }, onMenu: { phase = .menu })
            }
        }
    }

    private func startRun() {
        let model = SkylineGameModel(meta: meta, startingCoins: 0, ads: NoOpAdService())
        model.onRunOver = {
            summary = model.endRun()
            meta = model.session.meta
            SkylinePersistence.save(meta)
            phase = .gameOver
        }
        gameModel = model
        phase = .playing
    }
}
```

NOTE: `SkylineGameModel` needs `var scene: TowerScene` and
`var onRunOver: (() -> Void)?` added in Task 5's implementation — the model
owns the scene, forwards `onCollapse` to `handleCollapse`, and calls
`onRunOver` when `runOver` flips true. `windIncoming` is a published Bool the
model computes from its `WindSystem` schedule.

- [ ] **Step 2: Update GameForgeApp + delete demo files**

```swift
import SwiftUI

@main
struct GameForgeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

Delete `Sources/Game/DemoScene.swift` and `Sources/Game/GameView.swift`.

- [ ] **Step 3: Update StartScreen signature to match**

`StartScreen(coins: Int, level: Int, onStart: () -> Void, onShop: () -> Void)` — rewrite the existing file to this interface (keep the Monument Minimalism styling: sandstone gradient background, serif title).

- [ ] **Step 4: Commit**

```bash
git add -A Sources/
git commit -m "Wire Skyline Stack app navigation, remove demo game"
```

---

### Task 8: RevenueCat + AdMob SDK integration

**Files:**
- Modify: `project.yml` (add packages + keys)
- Modify: `Sources/App/PurchaseService.swift` (real RevenueCat calls)
- Modify: `Sources/App/AdService.swift` (real AdMob implementation)
- Modify: `Sources/App/GameForgeApp.swift` (configure services at launch)

**Interfaces:**
- Consumes: `PurchaseService`, `AdService` facades from Tasks 2–3.
- Produces: working IAP + rewarded ads on device; unchanged no-op behavior when unconfigured.

- [ ] **Step 1: Add SDKs to project.yml**

```yaml
packages:
  GameCore:
    path: Packages/GameCore
  RevenueCat:
    url: https://github.com/RevenueCat/purchases-ios.git
    from: 5.0.0
  GoogleMobileAds:
    url: https://github.com/googleads/googleads-mobile-ios-examples.git
    from: 11.0.0
```

And under the `GameForge` target `dependencies:` add:

```yaml
      - package: RevenueCat
      - package: GoogleMobileAds
      - package: GoogleMobileAds
```

(only once — one entry). Also add to the target settings:
`INFOPLIST_KEY_GADApplicationIdentifier: $(GAD_APPLICATION_IDENTIFIER)` and a
build setting `GAD_APPLICATION_IDENTIFIER` with a placeholder value
(`ca-app-pub-3940256099942544~1458002511` — Google's official test ID) so CI
builds work before the real AdMob account is set up.

- [ ] **Step 2: Wire RevenueCat into PurchaseService**

Replace the stub bodies:

```swift
import RevenueCat

func configure(apiKey: String?, onCoinsGranted: @escaping (Int) -> Void) {
    self.onCoinsGranted = onCoinsGranted
    guard let apiKey, !apiKey.isEmpty else { return }
    Purchases.logLevel = .warn
    Purchases.configure(with: apiKey)
    isConfigured = true
}

func refreshEntitlements() async {
    guard isConfigured else { return }
    let info = try? await Purchases.shared.customerInfo()
    removeAdsOwned = info?.entitlements["remove_ads"]?.isActive == true
    ownedPackIDs = Set(info?.activeSubscriptions ?? [])
}

func purchase(productID: String) async -> Bool {
    guard isConfigured else { return false }
    do {
        let products = try await Purchases.shared.products([productID])
        guard let product = products.first else { return false }
        let result = try await Purchases.shared.purchase(product: product)
        if result.userCancelled { return false }
        await refreshEntitlements()
        if let coins = Self.coinPackProductIDs[productID] {
            onCoinsGranted(coins)
        }
        if productID == Self.removeAdsProductID {
            removeAdsOwned = true
        }
        return true
    } catch {
        return false
    }
}
```

- [ ] **Step 3: Wire AdMob into AdService**

```swift
import GoogleMobileAds

final class AdMobService: NSObject, RewardedAdService, @unchecked Sendable {
    static let testUnitID = "ca-app-pub-3940256099942544/1712485313" // Google's official rewarded test ad

    private var rewarded: RewardedAd?
    private var loadedUnitID: String?

    static func configureIfNeeded() {
        if Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") != nil {
            MobileAds.shared.start(completionHandler: nil)
        }
    }

    func isReady() async -> Bool {
        await load()
        return rewarded != nil
    }

    private func load() async {
        let unitID = Self.testUnitID
        if loadedUnitID == unitID, rewarded != nil { return }
        rewarded = try? await RewardedAd.load(with: unitID, request: Request())
        loadedUnitID = unitID
    }

    func show(from viewController: UIViewController?) async -> Bool {
        guard let rewarded else { return false }
        return await withCheckedContinuation { continuation in
            rewarded.present(from: viewController ?? Self.topViewController()) {
                continuation.resume(returning: true)
            }
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
    }
}
```

- [ ] **Step 4: Configure at app launch**

In `GameForgeApp.init()`:

```swift
init() {
    AdMobService.configureIfNeeded()
    // RevenueCat key arrives via a build setting / xcconfig the owner adds
    // privately; empty string = unconfigured = game still fully works.
    // Task: read from Info.plist key REVENUECAT_API_KEY.
}
```

And in `RootView` init chain: `purchases.configure(apiKey: Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String, onCoinsGranted: { coins in /* add to game model economy */ })`.

- [ ] **Step 5: Verify build in CI**

Run: `git push` and watch `gh run list --repo nick7167/gameforge` — the `app-build-test` job must pass (xcodegen + xcodebuild + smoke tests).
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add project.yml Sources/App/PurchaseService.swift Sources/App/AdService.swift Sources/App/GameForgeApp.swift Sources/App/RootView.swift
git commit -m "Integrate RevenueCat and AdMob with graceful no-op fallback"
```

---

### Task 9: Game Center + polish pass

**Files:**
- Create: `Sources/App/GameCenterService.swift`
- Modify: `Sources/UI/StartScreen.swift` (daily challenge button + leaderboard entry)

**Interfaces:**
- Produces: `@MainActor final class GameCenterService` with `static func authenticate() async -> Bool`, `func submitDailyScore(_ height: Int, for date: Date) async`, `func showLeaderboard() async`. Leaderboard ID: `"daily.height"`. All calls no-op gracefully when Game Center is unavailable (simulator, not signed in).

- [ ] **Step 1: Implement GameCenterService**

```swift
import GameKit

@MainActor
final class GameCenterService {
    static let leaderboardID = "daily.height"

    static func authenticate() async {
        guard GKLocalPlayer.local.isAuthenticated == false else { return }
        GKLocalPlayer.local.authenticateHandler = { _, _ in }
    }

    func submitDailyHeight(_ height: Int) async {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let score = GKScore(leaderboardIdentifier: Self.leaderboardID)
        score.value = Int64(height)
        try? await GKScore.report([score])
    }

    func showLeaderboard() {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        // Present GKGameCenterViewController via the key window root.
        let vc = GKGameCenterViewController(leaderboardID: Self.leaderboardID, playerScope: .global, timeScope: .today)
        vc.gameCenterDelegate = nil
        Self.topViewController()?.present(vc, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
    }
}
```

- [ ] **Step 2: Add Game Center hooks**

- `GameForgeApp`: `Task { await GameCenterService.authenticate() }` at launch.
- `SkylineGameModel.endRun()`: after summary, `Task { await gameCenter.submitDailyHeight(summary.height) }` (inject `GameCenterService` into the model).

- [ ] **Step 3: Polish checklist (apply in same commit)**

- Placement juice: on `.placed(perfect: true)` play a chime + scale-bounce the node (SCNAction `scale` sequence); on `false` a duller thud.
- Collapse: slow-mo (`physicsWorld.timeScale = 0.25` for 1.5 s) + camera shake.
- Night lighting: after 20 districts, dim sun, add emissive window dots (small `SCNBox` children with `emission` material).
- Haptics: `UIImpactFeedbackGenerator` on placement, `UINotificationFeedbackGenerator(.error)` on collapse.

- [ ] **Step 4: Commit**

```bash
git add -A Sources/
git commit -m "Add Game Center leaderboards and juice polish pass"
```

---

### Task 10: Ship to TestFlight

**Files:**
- Modify: `AGENTS.md` (status)
- Modify: `docs/architecture.md` (app-layer components)

- [ ] **Step 1: Full local verification**

Run: `cd Packages/GameCore && swift test && swiftlint --config ../../.swiftlint.yml`
Expected: 55 tests PASS, 0 violations.

- [ ] **Step 2: Push and confirm CI green**

Run: `git push && gh run watch` (or `gh run list --repo nick7167/gameforge`)
Expected: all three CI jobs green (lint, gamecore-tests, app-build-test).

- [ ] **Step 3: Trigger TestFlight**

Run: `./scripts/trigger-testflight.sh`
Expected: build uploads; owner installs on device.

- [ ] **Step 4: Update docs**

- `AGENTS.md` CURRENT STATUS: "Skyline Stack app layer implemented — playable build on TestFlight."
- `docs/architecture.md`: add app-layer component table (TowerScene, SkylineGameModel, PurchaseService, AdService, GameCenterService, screens).

- [ ] **Step 5: Commit + push**

```bash
git add AGENTS.md docs/architecture.md
git commit -m "Document Skyline Stack app layer, ship first playable TestFlight build"
git push
```

---

## Plan Self-Review Notes

- **Spec coverage (app layer):** SceneKit physics/rendering + curing (Task 4), camera/input conventions (Task 4), HUD/lean meter (Task 5), revive offer with countdown + helper option (Task 6), shop with all 4 revenue streams (Task 6), Remove Ads perk wiring (Task 8), Game Center daily leaderboard (Task 9), slow-mo collapse + share (Tasks 9, 6), persistence (Task 1), no-backend constraint honored (RevenueCat/AdMob are third-party SDKs, no own backend), Monument Minimalism palette (Task 4 materials, Task 7 StartScreen).
- **Deliberate v1 simplifications:** placement slides on X only (Z fixed at 0) — matches Tower Bloxx drop-lane convention; camera is fixed-orbit (no pinch-zoom in v1 — follow-cam only); Coins persistence rides on `SkylineMeta` extension in Task 8 if needed; AdMob uses Google's official test unit ID until the owner creates a real account.
- **Type consistency:** `SkylineGameModel` (Task 5) is consumed by `RootView` (Task 7) with `scene`, `onRunOver`, `windIncoming` — flagged as additions to Task 5's contract. `PurchaseService.purchase(productID:)` signature consistent between Tasks 3/6/8. `RewardedAdService.show(from:)` used by Task 5's `reviveByAd()`.
- **Known risk:** SceneKit physics tuning (mass/lean mapping) is feel-work that only lands on device — flagged for TestFlight iteration, not blocking.