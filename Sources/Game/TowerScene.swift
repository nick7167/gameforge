import SceneKit
import GameCore

/// Renders the tower and runs rigid-body physics. Reports outcomes to the
/// app layer; all RULES live in GameCore (`SkylineSession`).
@MainActor
final class TowerScene: SCNScene {
  /// Reports (perfectPlacement) when a dropped district comes to rest.
  var onDistrictSettled: ((Bool) -> Void)?
  /// Reports a collapse cause when a placed district falls out of position.
  var onCollapse: ((CollapseCause) -> Void)?

  private var pendingNode: SCNNode?
  private var pendingType: DistrictType?
  private var slideVelocity: Float = 0.045
  private var slideDirection: Float = 1

  /// World Y at which each placed district node was dropped.
  private var placementHeights: [ObjectIdentifier: Float] = [:]
  private var collapseReported = false

  private let cellSize: Float = 1.0
  private let districtHeight: Float = 1.0
  private let gridHalf: Float = 3.0

  override init() {
    super.init()
    background.contents = skyGradient()
    setupLighting()
    setupFoundation()
    setupCamera()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("TowerScene is created in code")
  }

  /// Monument Minimalism sky: warm dawn gradient (deep plum → sand → gold).
  private func skyGradient() -> UIImage {
    let size = CGSize(width: 8, height: 64)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
      let colors = [
        UIColor(red: 0.23, green: 0.16, blue: 0.28, alpha: 1).cgColor,
        UIColor(red: 0.85, green: 0.66, blue: 0.48, alpha: 1).cgColor,
        UIColor(red: 0.98, green: 0.88, blue: 0.70, alpha: 1).cgColor
      ]
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0.0, 0.55, 1.0]
      )!
      ctx.cgContext.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 0, y: size.height),
        options: []
      )
    }
  }

  // MARK: Setup

  private func setupLighting() {
    // Key light: warm late-afternoon sun, casting soft shadows.
    let sun = SCNNode()
    sun.light = SCNLight()
    sun.light?.type = .directional
    sun.light?.intensity = 750
    sun.light?.color = UIColor(red: 1.0, green: 0.92, blue: 0.80, alpha: 1)
    sun.light?.castsShadow = true
    sun.light?.shadowMode = .deferred
    sun.light?.shadowSampleCount = 16
    sun.light?.shadowRadius = 6
    sun.light?.shadowColor = UIColor(red: 0.15, green: 0.10, blue: 0.18, alpha: 0.55)
    sun.eulerAngles = SCNVector3(-Float.pi / 3.2, Float.pi / 5, 0)
    rootNode.addChildNode(sun)

    // Ambient bounce: cool tint from the sky so shadows aren't dead black.
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 380
    ambient.light?.color = UIColor(red: 0.85, green: 0.80, blue: 0.95, alpha: 1)
    rootNode.addChildNode(ambient)
  }

  private func setupFoundation() {
    let side = CGFloat(gridHalf * 2 + 2)
    let geometry = SCNBox(width: side, height: 0.6, length: side, chamferRadius: 0.12)
    geometry.materials = [foundationMaterial()]
    let node = SCNNode(geometry: geometry)
    node.position = SCNVector3(0, -0.3, 0)
    node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
    node.name = "foundation"
    rootNode.addChildNode(node)
  }

  /// Sandstone base slab.
  private func foundationMaterial() -> SCNMaterial {
    let material = SCNMaterial()
    material.diffuse.contents = UIColor(red: 0.76, green: 0.62, blue: 0.47, alpha: 1)
    material.roughness.contents = 0.95
    material.lightingModel = .physicallyBased
    return material
  }

  private func setupCamera() {
    let cameraNode = SCNNode()
    cameraNode.camera = SCNCamera()
    cameraNode.camera?.fieldOfView = 45
    cameraNode.camera?.bloomIntensity = 0.25
    cameraNode.position = SCNVector3(11, 7, 11)
    cameraNode.look(at: SCNVector3(0, 1.5, 0))
    rootNode.addChildNode(cameraNode)
    cameraRig = cameraNode
  }

  private var cameraRig: SCNNode?

  /// Keeps the tower top framed as the tower grows.
  func followTowerTop(height: Float) {
    guard let camera = cameraRig else { return }
    let targetY = max(7.0, height * 0.6 + 4.0)
    let lookY = max(1.5, height * 0.55)
    let action = SCNAction.move(to: SCNVector3(11, targetY, 11), duration: 0.4)
    action.timingMode = .easeInEaseOut
    camera.runAction(action)
    camera.look(at: SCNVector3(0, lookY, 0))
  }

  // MARK: Placement

  private var placedCount: Int {
    rootNode.childNodes.filter { $0.name == "district" }.count
  }

  /// Creates the hovering next district, sliding along X for placement.
  func spawnDistrict(_ type: DistrictType) {
    removePending()
    pendingType = type
    let node = makeNode(for: type)
    node.name = "pending"
    node.simdPosition = simd_float3(-gridHalf, Float(placedCount) * districtHeight + 2.0, 0)
    rootNode.addChildNode(node)
    pendingNode = node
  }

  /// Removes the hovering pending district (public so the model can reset
  /// after an illegal placement).
  func removePending() {
    pendingNode?.removeFromParentNode()
    pendingNode = nil
    pendingType = nil
  }

  private func makeNode(for type: DistrictType) -> SCNNode {
    let side = CGFloat(Float(type.footprint) * cellSize)
    let geometry = SCNBox(width: side, height: CGFloat(districtHeight), length: side, chamferRadius: 0.05)
    geometry.materials = [material(for: type)]
    return SCNNode(geometry: geometry)
  }

  /// Monument Minimalism: sandstone/terracotta palette keyed by type id.
  private func material(for type: DistrictType) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    // Slightly deeper, warmer palette than before — the old colors washed out.
    let palette: [String: UIColor] = [
      "homes": UIColor(red: 0.93, green: 0.80, blue: 0.60, alpha: 1),
      "shops": UIColor(red: 0.85, green: 0.58, blue: 0.42, alpha: 1),
      "park": UIColor(red: 0.55, green: 0.66, blue: 0.40, alpha: 1),
      "office": UIColor(red: 0.62, green: 0.52, blue: 0.48, alpha: 1),
      "tower": UIColor(red: 0.88, green: 0.70, blue: 0.48, alpha: 1),
      "temple": UIColor(red: 0.78, green: 0.60, blue: 0.42, alpha: 1),
      "garden": UIColor(red: 0.48, green: 0.62, blue: 0.40, alpha: 1),
      "observatory": UIColor(red: 0.52, green: 0.48, blue: 0.55, alpha: 1)
    ]
    material.diffuse.contents = palette[type.id] ?? UIColor(red: 0.85, green: 0.72, blue: 0.52, alpha: 1)
    material.roughness.contents = 0.85
    material.metalness.contents = 0.0
    return material
  }

  /// Slides the pending district. Call once per frame from the SCNView delegate.
  func updateSlide() {
    guard let pending = pendingNode else { return }
    var x = pending.simdPosition.x + slideVelocity * slideDirection
    if x > gridHalf { x = gridHalf; slideDirection = -1 }
    if x < -gridHalf { x = -gridHalf; slideDirection = 1 }
    pending.simdPosition = simd_float3(x, pending.simdPosition.y, pending.simdPosition.z)
  }

  /// The current grid X of the pending district (snapped by GameCore rules).
  var pendingGridX: Int? {
    guard pendingNode != nil else { return nil }
    return Int(round(pendingNode!.simdPosition.x / cellSize))
  }

  /// Drops the pending district; physics takes over from here.
  func dropCurrentDistrict() {
    guard let pending = pendingNode, let type = pendingType else { return }
    pending.name = "district"
    let gridX = Int(round(pending.simdPosition.x / cellSize))
    pending.simdPosition = simd_float3(Float(gridX) * cellSize, pending.simdPosition.y, pending.simdPosition.z)
    let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: pending.geometry!, options: nil))
    body.mass = CGFloat(type.weight)
    body.allowsResting = true
    body.damping = 0.6
    body.angularDamping = 0.8
    pending.physicsBody = body
    placementHeights[ObjectIdentifier(pending)] = pending.simdPosition.y
    pendingNode = nil
    pendingType = nil
    playDropJuice(on: pending)
  }

  /// Placement feedback: squash-and-stretch scale pulse on the block.
  private func playDropJuice(on node: SCNNode) {
    let squash = SCNAction.scale(to: 0.82, duration: 0.07)
    squash.timingMode = .easeIn
    let recover = SCNAction.scale(to: 1.0, duration: 0.22)
    recover.timingMode = .easeOut
    node.runAction(.sequence([squash, recover]))
  }

  /// Removes the top placed district (collapse) with a small pop animation.
  func removeTopDistrict() {
    guard let top = rootNode.childNodes.filter({ $0.name == "district" }).last else { return }
    top.name = "falling"
    placementHeights.removeValue(forKey: ObjectIdentifier(top))
    collapseReported = false
    // Fade the lost district out as it tumbles away.
    top.runAction(.sequence([
      .wait(duration: 1.2),
      .fadeOpacity(to: 0.0, duration: 0.5),
      .removeFromParentNode()
    ]))
  }

  // MARK: Physics feedback

  /// Called once per frame: animates the slide and detects fallen districts.
  func tick() {
    updateSlide()
    for node in rootNode.childNodes where node.name == "district" {
      guard let placedY = placementHeights[ObjectIdentifier(node)] else { continue }
      if node.presentation.simdPosition.y < placedY - 2.0, !collapseReported {
        collapseReported = true
        onCollapse?(.impact)
      }
      // Curing: near-zero velocity for a settled body → freeze it.
      // SCNPhysicsBody.velocity is an SCNVector3 of Floats; compute the
      // magnitude manually (no .length() member).
      if let body = node.physicsBody, body.type == .dynamic {
        let velocity = body.velocity
        let speed = (velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z).squareRoot()
        if speed < 0.05, node.presentation.position.y > 0 {
          body.type = .static
          onDistrictSettled?(true)
        }
      }
    }
  }

  /// Freezes physics for `seconds` (Stabilize & Continue revive).
  func stabilize(seconds: TimeInterval) {
    physicsWorld.speed = 0
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
      self?.physicsWorld.speed = 1
    }
  }

  /// Applies a wind impulse to all dynamic (uncured) districts.
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

  /// Slow-motion collapse effect.
  func playSlowMotion() {
    // SCNPhysicsWorld has no timeScale; simulate slow-mo by pausing physics
    // briefly, then resuming (visual pacing handled by the camera/HUD).
    physicsWorld.speed = 0.25
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      self?.physicsWorld.speed = 1
    }
  }
}
