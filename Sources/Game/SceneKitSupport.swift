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
    let inner = SCNNode(geometry: SCNRing(innerRadius: 0.72, outerRadius: 0.95))
    inner.geometry?.materials = [flatMaterial(hex: hex, additive: true)]
    let outer = SCNNode(geometry: SCNRing(innerRadius: 0.98, outerRadius: 1.04))
    outer.geometry?.materials = [flatMaterial(hex: hex, additive: true)]
    for ring in [inner, outer] {
      ring.eulerAngles.x = -.pi / 2 // SCNRing lies in the XY plane; lay it flat on the stage
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
    // SCNMatrix4MakeTranslation takes CGFloat; boundingBox components are Float on iOS.
    node.pivot = SCNMatrix4MakeTranslation(CGFloat((maxBound.x - minBound.x) / 2), 0, 0)
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = .Y
    node.constraints = [billboard]
    return node
  }
}
