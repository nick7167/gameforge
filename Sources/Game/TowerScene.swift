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
    setupLighting()
    setupFoundation()
    setupCamera()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("TowerScene is created in code")
  }

  // MARK: Setup

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

  private func setupFoundation() {
    let side = CGFloat(gridHalf * 2 + 2)
    let geometry = SCNBox(width: side, height: 0.6, length: side, chamferRadius: 0.1)
    let material = SCNMaterial()
    material.diffuse.contents = UIColor(red: 0.82, green: 0.74, blue: 0.62, alpha: 1)
    material.roughness.contents = 0.95
    geometry.materials = [material]
    let node = SCNNode(geometry: geometry)
    node.position = SCNVector3(0, -0.3, 0)
    node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
    node.name = "foundation"
    rootNode.addChildNode(node)
  }

  private func setupCamera() {
    let cameraNode = SCNNode()
    cameraNode.camera = SCNCamera()
    cameraNode.camera?.fieldOfView = 55
    cameraNode.position = SCNVector3(9, 8, 9)
    cameraNode.look(at: SCNVector3(0, 2, 0))
    rootNode.addChildNode(cameraNode)
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
    node.position = SCNVector3(-gridHalf, Float(placedCount) * districtHeight + 2.0, 0)
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

  /// Slides the pending district. Call once per frame from the SCNView delegate.
  func updateSlide() {
    guard let pending = pendingNode else { return }
    var x = pending.position.x + slideVelocity * slideDirection
    if x > gridHalf { x = gridHalf; slideDirection = -1 }
    if x < -gridHalf { x = -gridHalf; slideDirection = 1 }
    pending.position.x = x
  }

  /// The current grid X of the pending district (snapped by GameCore rules).
  var pendingGridX: Int? {
    guard pendingNode != nil else { return nil }
    return Int(round(pendingNode!.position.x / cellSize))
  }

  /// Drops the pending district; physics takes over from here.
  func dropCurrentDistrict() {
    guard let pending = pendingNode, let type = pendingType else { return }
    pending.name = "district"
    let gridX = Int(round(pending.position.x / cellSize))
    pending.position.x = Float(gridX) * cellSize
    let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: pending.geometry!, options: nil))
    body.mass = Float(type.weight)
    body.allowsResting = true
    body.damping = 0.6
    body.angularDamping = 0.8
    pending.physicsBody = body
    placementHeights[ObjectIdentifier(pending)] = pending.position.y
    pendingNode = nil
    pendingType = nil
  }

  /// Removes the top placed district (collapse) with a small pop animation.
  func removeTopDistrict() {
    guard let top = rootNode.childNodes.filter({ $0.name == "district" }).last else { return }
    top.name = "falling"
    placementHeights.removeValue(forKey: ObjectIdentifier(top))
    collapseReported = false
  }

  // MARK: Physics feedback

  /// Called once per frame: animates the slide and detects fallen districts.
  func tick() {
    updateSlide()
    for node in rootNode.childNodes where node.name == "district" {
      guard let placedY = placementHeights[ObjectIdentifier(node)] else { continue }
      if node.presentation.position.y < placedY - 2.0, !collapseReported {
        collapseReported = true
        onCollapse?(.impact)
      }
      // Curing: near-zero velocity for a settled body → freeze it.
      // SCNNode has no `velocity`; use the physics body's velocity instead.
      if let body = node.physicsBody, body.type == .dynamic,
         body.velocity.length() < 0.05, node.presentation.position.y > 0 {
        body.type = .static
        onDistrictSettled?(true)
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
