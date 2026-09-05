import SceneKit
import UIKit
import GameCore

/// Pure factory helpers for the SceneKit battle stage. No state, no game rules.
enum SceneKitSupport {
  /// Scene-facing faction tints (saturated variants of the DS faction palette).
  static func factionHex(_ faction: Faction) -> UInt32 {
    switch faction {
    case .ember: 0xFF7A2A
    case .frost: 0x4FC3F7
    case .verdant: 0x7ED957
    case .void: 0x9C6EFF
    }
  }

  /// 0xRRGGBB → UIColor.
  static func uiColor(hex: UInt32) -> UIColor {
    UIColor(
      red: CGFloat((hex >> 16) & 0xFF) / 255.0,
      green: CGFloat((hex >> 8) & 0xFF) / 255.0,
      blue: CGFloat(hex & 0xFF) / 255.0,
      alpha: 1)
  }

  /// Unlit emissive material for glow elements (rune ring, stage circles, eyes).
  static func glowMaterial(hex: UInt32, intensity: CGFloat) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.emission.contents = uiColor(hex: hex)
    material.emission.intensity = intensity
    return material
  }

  /// Unlit diffuse material; `additive` blends on top of the scene for rings and flash planes.
  static func flatMaterial(hex: UInt32, additive: Bool = false) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = uiColor(hex: hex)
    if additive {
      material.blendMode = .add
      material.isDoubleSided = true
      material.writesToDepthBuffer = false
    }
    return material
  }

  /// Two concentric additive rings — the faction-colored stage circle under a unit.
  static func stageCircle(hex: UInt32) -> SCNNode {
    let group = SCNNode()
    let inner = SCNNode(geometry: SCNTube(innerRadius: 0.72, outerRadius: 0.95, height: 0.02))
    inner.geometry?.materials = [flatMaterial(hex: hex, additive: true)]
    let outer = SCNNode(geometry: SCNTube(innerRadius: 0.98, outerRadius: 1.04, height: 0.02))
    outer.geometry?.materials = [flatMaterial(hex: hex, additive: true)]
    for ring in [inner, outer] {
      // SCNTube's axis is Y, so the rings already lie flat on the stage floor.
      ring.position = SCNVector3(0, 0.06, 0)
      group.addChildNode(ring)
    }
    return group
  }

  /// Billboarded text label (SCNText with a flat unlit material), centered horizontally.
  static func billboardText(_ text: String, size: CGFloat, color: UIColor) -> SCNNode {
    let geometry = SCNText(string: text, extrusionDepth: 0)
    geometry.font = UIFont.systemFont(ofSize: size, weight: .bold)
    geometry.flatness = 0.2
    geometry.firstMaterial?.lightingModel = .constant
    geometry.firstMaterial?.diffuse.contents = color
    let node = SCNNode(geometry: geometry)
    node.scale = SCNVector3(0.01, 0.01, 0.01)
    let (minBound, maxBound) = node.boundingBox
    // boundingBox components are Float on iOS; SCNMatrix4MakeTranslation takes Float.
    node.pivot = SCNMatrix4MakeTranslation((maxBound.x - minBound.x) / 2, 0, 0)
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = .Y
    node.constraints = [billboard]
    return node
  }
}
