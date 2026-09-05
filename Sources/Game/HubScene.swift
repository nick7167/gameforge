import GameCore
import QuartzCore
import SceneKit
import UIKit

/// Scene hex palette — mirrors the battle stage's dusk language.
private enum HubHex {
  static let sky = UInt32(0x1A0F2A)
  static let fog = UInt32(0x120A1E)
  static let platform = UInt32(0x3A2C50)
  static let runeRing = UInt32(0xFF8C42)
  static let ambient = UInt32(0x4A3A6A)
  static let key = UInt32(0xFFD9A0)
  static let rimOrange = UInt32(0xFF8C42)
  static let rimBlue = UInt32(0x6A8CFF)
  static let ember = UInt32(0xFFA050)
  static let skin = UInt32(0xF0C8A0)
  static let label = UInt32(0xFFE9C0)
  static let stone = UInt32(0x5A4A78)
  static let stoneDark = UInt32(0x4A3A5C)
  static let wood = UInt32(0x7A4A2A)
}

/// Portrait-framed 3D stronghold: the world hub. Buildings are tappable
/// buttons (hit-tested by node name), squad heroes wander the platform.
/// The scene owns zero game rules — taps surface as `BuildingAction` values.
@MainActor
final class HubScene {
  enum BuildingAction {
    case battle, summon, heroes, shop
    case locked(label: String)
  }

  static let buildingPrefix = "building-"
  static let heroPrefix = "hero-"

  let scene = SCNScene()
  private var cameraNode: SCNNode?

  init(squad: [(id: String, name: String, faction: Faction)]) {
    buildSky()
    buildArena()
    buildBuildings()
    buildLights()
    buildEmbers()
    buildCamera()
    spawnHeroes(squad)
  }

  // MARK: - Environment

  private func buildSky() {
    let dome = SCNNode(geometry: SCNSphere(radius: 90))
    dome.geometry?.firstMaterial?.lightingModel = .constant
    dome.geometry?.firstMaterial?.diffuse.contents = SceneKitSupport.uiColor(hex: HubHex.sky)
    dome.geometry?.firstMaterial?.cullMode = .front // render the inside of the sphere
    scene.rootNode.addChildNode(dome)

    scene.fog = SCNFog()
    scene.fog?.color = SceneKitSupport.uiColor(hex: HubHex.fog)
    scene.fog?.start = 25
    scene.fog?.end = 90
  }

  private func buildArena() {
    let disc = SCNCylinder(radiusTop: 7, radiusBottom: 7.4, height: 0.6)
    disc.radialSegmentCount = 64
    let material = SCNMaterial()
    material.lightingModel = .lambert
    material.diffuse.contents = SceneKitSupport.uiColor(hex: HubHex.platform)
    disc.materials = [material]
    let platform = SCNNode(geometry: disc)
    // Top surface lands at y = 0 so buildings and heroes stand on it.
    platform.position = SCNVector3(0, -0.3, 0)
    scene.rootNode.addChildNode(platform)

    let runeRing = SCNNode(geometry: SCNTorus(ringRadius: 6.7, pipeRadius: 0.08))
    runeRing.geometry?.materials = [SceneKitSupport.glowMaterial(hex: HubHex.runeRing, intensity: 1.6)]
    runeRing.position = SCNVector3(0, 0.06, 0)
    scene.rootNode.addChildNode(runeRing)
  }

  private func buildLights() {
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.color = SceneKitSupport.uiColor(hex: HubHex.ambient)
    ambient.light?.intensity = 400
    scene.rootNode.addChildNode(ambient)

    let key = SCNNode()
    key.light = SCNLight()
    key.light?.type = .directional
    key.light?.color = SceneKitSupport.uiColor(hex: HubHex.key)
    key.light?.castsShadow = false // simulator/CI safety: no shadow maps
    key.look(at: SCNVector3(0, 1, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    key.position = SCNVector3(-8, 14, 6)
    scene.rootNode.addChildNode(key)

    addRimLight(hex: HubHex.rimOrange, position: SCNVector3(-6, 4, -8))
    addRimLight(hex: HubHex.rimBlue, position: SCNVector3(8, 5, -8))
  }

  private func addRimLight(hex: UInt32, position: SCNVector3) {
    let rim = SCNNode()
    rim.light = SCNLight()
    rim.light?.type = .directional
    rim.light?.color = SceneKitSupport.uiColor(hex: hex)
    rim.position = position
    rim.look(at: SCNVector3(0, 1.5, 0))
    scene.rootNode.addChildNode(rim)
  }

  private func buildEmbers() {
    let emitters = SCNParticleSystem()
    emitters.emitterShape = SCNPlane(width: 18, height: 18)
    emitters.particleColor = SceneKitSupport.uiColor(hex: HubHex.ember)
    emitters.particleSize = 0.05
    emitters.particleVelocity = 0.5
    emitters.particleVelocityVariation = 0.2
    emitters.emissionDuration = 1
    emitters.emissionDurationVariation = 1
    emitters.loops = true
    emitters.particleLifeSpan = 8
    emitters.birthRate = 5 // ≈ 40 embers alive at any moment
    emitters.blendMode = .additive
    let emberNode = SCNNode()
    emberNode.position = SCNVector3(0, -0.5, 0)
    emberNode.eulerAngles.x = -.pi / 2 // point the emitter plane's normal up so embers float
    emberNode.addParticleSystem(emitters)
    scene.rootNode.addChildNode(emberNode)
  }

  private func buildCamera() {
    let camera = SCNCamera()
    camera.fieldOfView = 42
    let node = SCNNode()
    node.camera = camera
    node.position = SCNVector3(0, 8, 14)
    node.look(at: SCNVector3(0, 2, 0))
    node.runAction(Self.cameraDrift())
    cameraNode = node
    scene.rootNode.addChildNode(node)
  }

  /// Subtle idle sway: slow ease-in-out oscillation around the anchor pose.
  private static func cameraDrift() -> SCNAction {
    let forward = SCNAction.moveBy(x: 0.5, y: 0.2, z: 0, duration: 5)
    let back = SCNAction.moveBy(x: -0.5, y: -0.2, z: 0, duration: 5)
    for action in [forward, back] {
      action.timingMode = .easeInEaseOut
    }
    return .repeatForever(.sequence([forward, back]))
  }

  // MARK: - Heroes

  /// Squad members wander between three waypoints on the platform.
  private func spawnHeroes(_ squad: [(id: String, name: String, faction: Faction)]) {
    for (index, hero) in squad.prefix(5).enumerated() {
      let figure = heroFigure(faction: hero.faction)
      figure.name = Self.heroPrefix + hero.id
      let base = Double(index) * 2 * .pi / 5
      let waypoints = [
        waypoint(angle: base, radius: 4.4),
        waypoint(angle: base + 0.8, radius: 3.2),
        waypoint(angle: base - 0.9, radius: 5.0),
      ]
      figure.position = waypoints[0]
      figure.runAction(walkAction(waypoints: waypoints))
      scene.rootNode.addChildNode(figure)
    }
  }

  private func waypoint(angle: Double, radius: Double) -> SCNVector3 {
    SCNVector3(Float(cos(angle) * radius), 0, Float(sin(angle) * radius))
  }

  private func walkAction(waypoints: [SCNVector3]) -> SCNAction {
    var steps: [SCNAction] = []
    for (index, target) in waypoints.enumerated() {
      let move = SCNAction.move(to: target, duration: 2.4)
      move.timingMode = .easeInEaseOut
      steps.append(move)
      steps.append(.wait(duration: Double(1 + index % 2)))
    }
    return .repeatForever(.sequence(steps))
  }

  /// Local simplified figure: faction-colored capsule body + skin sphere head.
  private func heroFigure(faction: Faction) -> SCNNode {
    let root = SCNNode()

    let body = SCNNode(geometry: SCNCapsule(capRadius: 0.3, height: 0.6))
    body.position = SCNVector3(0, 0.55, 0)
    body.geometry?.firstMaterial?.lightingModel = .lambert
    body.geometry?.firstMaterial?.diffuse.contents =
      SceneKitSupport.uiColor(hex: SceneKitSupport.factionHex(faction))
    root.addChildNode(body)

    let head = SCNNode(geometry: SCNSphere(radius: 0.22))
    head.position = SCNVector3(0, 1.08, 0)
    head.geometry?.firstMaterial?.lightingModel = .lambert
    head.geometry?.firstMaterial?.diffuse.contents = SceneKitSupport.uiColor(hex: HubHex.skin)
    root.addChildNode(head)

    root.scale = SCNVector3(0.8, 0.8, 0.8)
    return root
  }

  // MARK: - Input

  /// Hit-tests the tap point and maps the enclosing building node to an action.
  /// Hero taps return nil (heroes are decoration, not buttons).
  func handleTap(at point: CGPoint, in scnView: SCNView) -> BuildingAction? {
    for hit in scnView.hitTest(point, options: nil) {
      var current: SCNNode? = hit.node
      while let node = current {
        guard let name = node.name else {
          current = node.parentNode
          continue
        }
        if name.hasPrefix(Self.buildingPrefix) {
          return Self.action(forBuilding: String(name.dropFirst(Self.buildingPrefix.count)))
        }
        if name.hasPrefix(Self.heroPrefix) {
          return nil
        }
        current = node.parentNode
      }
    }
    return nil
  }

  private static func action(forBuilding id: String) -> BuildingAction {
    switch id {
    case "portal": .battle
    case "tavern": .summon
    case "forge": .heroes
    case "merchant": .shop
    case "arenaGate": .locked(label: "Arena")
    case "tower": .locked(label: "Tower")
    case "guildHall": .locked(label: "Guild Hall")
    default: .locked(label: "This area")
    }
  }
}
