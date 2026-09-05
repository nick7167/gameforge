import QuartzCore
import SceneKit
import UIKit
import GameCore

/// Scene hex palette — dusk purple base with orange/gold glow accents (prototype-verified).
private enum Hex {
  static let sky = UInt32(0x1A0F2A)
  static let fog = UInt32(0x120A1E)
  static let arena = UInt32(0x3A2C50)
  static let runeRing = UInt32(0xFF8C42)
  static let ambient = UInt32(0x4A3A6A)
  static let key = UInt32(0xFFD9A0)
  static let rimOrange = UInt32(0xFF8C42)
  static let rimBlue = UInt32(0x6A8CFF)
  static let ember = UInt32(0xFFA050)
  static let skin = UInt32(0xF0C8A0)
  static let heroHP = UInt32(0x5DD879)
  static let enemyHP = UInt32(0xE57373)
  static let gold = UInt32(0xFFD76A)
  static let hpTrack = UInt32(0x1C1428)
}

/// SceneKit renderer for the battle stage. Mirrors `BattleEngine` state into nodes;
/// owns zero game rules. Visual language from the approved prototype: dusk sky,
/// glowing stage circles, warm key + faction rims, embers. Pure kinematics — no physics.
@MainActor
final class BattleScene {
  struct BattleEvents {
    var onDamageNumber: ((String, String, DamageKind) -> Void)?
    var onUnitDied: ((String) -> Void)?
    var onUltimateCharged: ((String) -> Void)?
    var onUltFlash: (() -> Void)?
  }

  enum DamageKind { case normal, crit, ult, heal }

  let scene = SCNScene()
  private var heroNodes: [String: SCNNode] = [:]
  private var enemyNodes: [String: SCNNode] = [:]
  private var lastUltCharge: [String: Double] = [:]
  private var hpBars: [String: SCNNode] = [:]
  private var previousHP: [String: Double] = [:]
  private var events = BattleEvents()
  private var cameraNode: SCNNode?
  private var shakeStart: CFTimeInterval?

  init(engine: BattleEngine) {
    buildSky()
    buildArena()
    buildLights()
    buildEmbers()
    buildCamera()
    for (index, unit) in engine.heroes.enumerated() {
      spawnUnit(unit, x: -6.4 - Double(index) * 0.8, z: index % 2 == 0 ? 1.5 : -1.5)
    }
    for (index, unit) in engine.enemies.enumerated() {
      spawnUnit(unit, x: 5.6 + Double(index) * 0.8, z: index % 2 == 0 ? -1.5 : 1.5)
    }
    // Seed previous HP after spawning so the first sync never reports phantom damage.
    for unit in engine.heroes + engine.enemies {
      previousHP[unit.id] = unit.hp
      lastUltCharge[unit.id] = unit.ultCharge
    }
  }

  // MARK: - Environment

  private func buildSky() {
    let dome = SCNNode(geometry: SCNSphere(radius: 90))
    dome.geometry?.firstMaterial?.lightingModel = .constant
    dome.geometry?.firstMaterial?.diffuse.contents = SceneKitSupport.uiColor(hex: Hex.sky)
    dome.geometry?.firstMaterial?.cullMode = .front // render the inside of the sphere
    scene.rootNode.addChildNode(dome)
  }

  private func buildArena() {
    // Truncated-cone arena disc: slightly wider at the base.
    let disc = SCNCone(topRadius: 11, bottomRadius: 12.5, height: 1.4)
    disc.radialSegmentCount = 64
    let material = SCNMaterial()
    material.lightingModel = .lambert
    material.diffuse.contents = SceneKitSupport.uiColor(hex: Hex.arena)
    disc.materials = [material]
    let arena = SCNNode(geometry: disc)
    arena.position = SCNVector3(0, -0.7, 0)
    scene.rootNode.addChildNode(arena)

    let runeRing = SCNNode(geometry: SCNTorus(ringRadius: 10.4, pipeRadius: 0.09))
    runeRing.geometry?.materials = [SceneKitSupport.glowMaterial(hex: Hex.runeRing, intensity: 1.6)]
    runeRing.position = SCNVector3(0, 0.06, 0)
    scene.rootNode.addChildNode(runeRing)
  }

  private func buildLights() {
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.color = SceneKitSupport.uiColor(hex: Hex.ambient)
    ambient.light?.intensity = 400
    scene.rootNode.addChildNode(ambient)

    let key = SCNNode()
    key.light = SCNLight()
    key.light?.type = .directional
    key.light?.color = SceneKitSupport.uiColor(hex: Hex.key)
    key.light?.castsShadow = false // simulator/CI safety: no shadow maps
    key.look(at: SCNVector3(0, 1, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    key.position = SCNVector3(-8, 14, 6)
    scene.rootNode.addChildNode(key)

    addRimLight(hex: Hex.rimOrange, position: SCNVector3(-6, 4, -8))
    addRimLight(hex: Hex.rimBlue, position: SCNVector3(8, 5, -8))
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
    emitters.emitterShape = SCNPlane(width: 24, height: 24)
    emitters.particleColor = SceneKitSupport.uiColor(hex: Hex.ember)
    emitters.particleSize = 0.05
    emitters.particleVelocity = 0.5
    emitters.particleVelocityVariation = 0.2
    emitters.emissionDuration = 1
    emitters.emissionDurationVariation = 1
    emitters.loops = true
    emitters.particleLifeSpan = 8
    emitters.birthRate = 6 // ≈ 48 embers alive at any moment
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
    node.position = SCNVector3(0, 7.2, 20.5)
    node.look(at: SCNVector3(0, 2.2, 0))
    cameraNode = node
    scene.rootNode.addChildNode(node)
  }

  // MARK: - Units

  private func spawnUnit(_ unit: BattleEngine.Unit, x: Double, z: Double) {
    let root = SCNNode()
    root.position = SCNVector3(Float(x), 0, Float(z))
    if unit.isBoss {
      root.scale = SCNVector3(1.5, 1.5, 1.5)
    }

    let torso = SCNNode(geometry: SCNCapsule(capRadius: 0.42, height: 0.75))
    torso.position = SCNVector3(0, 1.05, 0)
    torso.geometry?.firstMaterial?.lightingModel = .lambert
    torso.geometry?.firstMaterial?.diffuse.contents = SceneKitSupport.uiColor(hex: SceneKitSupport.factionHex(unit.def.faction))
    root.addChildNode(torso)

    let head = SCNNode(geometry: SCNSphere(radius: 0.34))
    head.position = SCNVector3(0, 1.78, 0)
    head.geometry?.firstMaterial?.lightingModel = .lambert
    head.geometry?.firstMaterial?.diffuse.contents = SceneKitSupport.uiColor(hex: Hex.skin)
    root.addChildNode(head)

    for eyeX: Float in [-0.12, 0.12] {
      let eye = SCNNode(geometry: SCNSphere(radius: 0.05))
      eye.position = SCNVector3(eyeX, 1.84, 0.3)
      eye.geometry?.firstMaterial = SceneKitSupport.glowMaterial(hex: Hex.ember, intensity: 1.4)
      root.addChildNode(eye)
    }

    root.addChildNode(SceneKitSupport.stageCircle(hex: SceneKitSupport.factionHex(unit.def.faction)))

    let (barHolder, barFill) = makeHPBar(unit: unit)
    barHolder.position = SCNVector3(0, unit.isBoss ? 3.4 : 2.9, 0)
    root.addChildNode(barHolder)
    hpBars[unit.id] = barFill

    scene.rootNode.addChildNode(root)
    if unit.isEnemy {
      enemyNodes[unit.id] = root
    } else {
      heroNodes[unit.id] = root
    }
  }

  /// Dark track plane + fill plane pivoted at its left edge so scale.x drains right-to-left.
  private func makeHPBar(unit: BattleEngine.Unit) -> (holder: SCNNode, fill: SCNNode) {
    let holder = SCNNode()
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = .Y
    holder.constraints = [billboard]

    let track = SCNNode(geometry: SCNPlane(width: 1.15, height: 0.16))
    track.geometry?.materials = [SceneKitSupport.flatMaterial(hex: Hex.hpTrack)]
    holder.addChildNode(track)

    let fillNode = SCNNode(geometry: SCNPlane(width: 1.1, height: 0.12))
    fillNode.geometry?.materials = [
      SceneKitSupport.flatMaterial(hex: unit.isEnemy ? Hex.enemyHP : Hex.heroHP)
    ]
    // Pivot at the left edge so scale.x drains right-to-left.
    var pivot = SCNMatrix4Identity
    pivot.m41 = -0.55
    fillNode.pivot = pivot
    fillNode.position = SCNVector3(-0.55, 0, 0.01)
    holder.addChildNode(fillNode)

    return (holder, fillNode)
  }

  // MARK: - Sync

  /// Mirror engine state into nodes. Called every tick by the view layer.
  func sync(engine: BattleEngine, events: BattleEvents) {
    self.events = events
    for unit in engine.heroes {
      syncUnit(unit, node: heroNodes[unit.id], elapsed: engine.elapsed, events: events)
    }
    for unit in engine.enemies {
      syncUnit(unit, node: enemyNodes[unit.id], elapsed: engine.elapsed, events: events)
    }
    updateCamera(elapsed: engine.elapsed)
  }

  private func syncUnit(_ unit: BattleEngine.Unit, node: SCNNode?, elapsed: Double, events: BattleEvents) {
    guard let node else { return }

    let hash = unit.id.unicodeScalars.reduce(0) { $0 &+ $1.value }
    let bobPhase = Float(hash % 100) / 100 * Float.pi * 2
    node.position.y = sin(Float(elapsed) * 2.2 + bobPhase) * 0.06

    let previous = previousHP[unit.id] ?? unit.hp
    if previous > 0, !unit.isAlive {
      previousHP[unit.id] = 0
      events.onUnitDied?(unit.id)
      let sink = SCNAction.moveBy(x: 0, y: -1.2, z: 0, duration: 1)
      sink.timingMode = .easeIn
      node.runAction(.sequence([.group([.fadeOut(duration: 1), sink]), .removeFromParentNode()]))
      return
    }

    if unit.isAlive, unit.hp < previous {
      let delta = previous - unit.hp
      let kind: DamageKind = delta > unit.maxHP * 0.18 ? .crit : .normal
      events.onDamageNumber?(unit.id, "-\(Int(delta.rounded()))", kind)
    }

    if unit.isAlive, let last = lastUltCharge[unit.id], last < 1, unit.ultCharge >= 1 {
      events.onUltimateCharged?(unit.id)
    }
    lastUltCharge[unit.id] = unit.ultCharge

    previousHP[unit.id] = unit.hp

    if let fill = hpBars[unit.id] {
      let ratio = max(0, min(1, unit.hp / unit.maxHP))
      fill.scale = SCNVector3(Float(ratio), 1, 1)
    }
  }

  private func updateCamera(elapsed: Double) {
    guard let cameraNode else { return }
    let time = Float(elapsed)
    var offsetX = sin(time * 0.31) * 0.4
    var offsetY = sin(time * 0.23) * 0.18
    if let shakeStart {
      let shakeT = Float(CACurrentMediaTime() - shakeStart)
      if shakeT < 0.4 {
        let decay = (0.4 - shakeT) / 0.4
        offsetX += sin(shakeT * 70) * 0.22 * decay
        offsetY += cos(shakeT * 63) * 0.16 * decay
      } else {
        self.shakeStart = nil
      }
    }
    cameraNode.position = SCNVector3(offsetX, 7.2 + offsetY, 20.5)
    cameraNode.look(at: SCNVector3(sin(time * 0.2) * 0.6, 2.2, 0))
  }

  // MARK: - Projection

  /// Screen-space position above a unit's head for HUD overlays. Projects the
  /// node's world position with a 2.4-unit y-offset; nil when the node is
  /// missing or outside the view frustum.
  func unitScreenPosition(unitID: String, in scnView: SCNView) -> CGPoint? {
    let node = heroNodes[unitID] ?? enemyNodes[unitID]
    guard let node else { return nil }
    let world = node.worldPosition
    let projected = scnView.projectPoint(SCNVector3(world.x, world.y + 2.4, world.z))
    // z outside 0...1 means behind the camera or clipped.
    guard projected.z >= 0, projected.z <= 1 else { return nil }
    return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
  }

  // MARK: - Ultimates

  /// Camera shake + particle burst at the target; the view layer flashes via `onUltFlash`.
  func playUltimate(heroID: String, result: BattleEngine.UltFireResult) {
    events.onUltFlash?()
    shakeStart = CACurrentMediaTime()
    if let targetID = result.targetID {
      burst(at: enemyNodes[targetID] ?? heroNodes[targetID])
    }
    _ = heroID // reserved: per-hero ultimate VFX (launcher pose, weapon trail) in a later pass
  }

  private func burst(at node: SCNNode?) {
    guard let node else { return }
    let particles = SCNParticleSystem()
    particles.particleColor = SceneKitSupport.uiColor(hex: Hex.gold)
    particles.particleSize = 0.1
    particles.particleVelocity = 3
    particles.particleVelocityVariation = 2.5
    particles.emissionDuration = 0.05
    particles.loops = false
    particles.particleLifeSpan = 0.45
    particles.birthRate = 1200 // 0.05s × 1200 ≈ 60 particles
    particles.blendMode = .additive
    node.addParticleSystem(particles)
  }
}
