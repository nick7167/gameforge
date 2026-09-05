import SceneKit
import UIKit

/// Construction of the hub's tappable buildings. Kept in an extension to keep
/// `HubScene.swift` under the lint file-length budget. Each building root is
/// named `building-<id>` so `HubScene.handleTap` can map hits to actions.
extension HubScene {
  private enum LockedHex {
    static let arenaGate = UInt32(0x9C6EFF)
    static let tower = UInt32(0x8AD4FF)
    static let guildHall = UInt32(0xC9A8FF)
  }

  private func buildBuildings() {
    addBuilding(
      id: "portal", label: "BATTLE", position: (0, -3),
      accentHex: 0xFF8C42) {
        portalComposition()
      }
    addBuilding(
      id: "tavern", label: "TAVERN", position: (-3.2, 0.5),
      accentHex: 0x4FC3F7) {
        tavernComposition()
      }
    addBuilding(
      id: "forge", label: "FORGE", position: (3.2, 0.5),
      accentHex: 0xFF7A2A) {
        forgeComposition()
      }
    addBuilding(
      id: "merchant", label: "SHOP", position: (1.8, -2.2),
      accentHex: 0xFFD76A) {
        merchantComposition()
      }

    // Locked content (v1.5 / v2): dimmed, no glow pulse.
    addBuilding(
      id: "arenaGate", label: "ARENA", position: (-1.8, -2.2),
      accentHex: LockedHex.arenaGate, locked: true) {
        arenaGateComposition()
      }
    addBuilding(
      id: "tower", label: "TOWER", position: (0, 2.2),
      accentHex: LockedHex.tower, locked: true) {
        towerComposition()
      }
    addBuilding(
      id: "guildHall", label: "GUILD", position: (4.2, 2.2),
      accentHex: LockedHex.guildHall, locked: true) {
        guildHallComposition()
      }
  }

  /// Assembles a building root: composition + name label + accent glow,
  /// dims everything when `locked`, pulses the accent when unlocked.
  private func addBuilding(
    id: String,
    label: String,
    position: (x: Double, z: Double),
    accentHex: UInt32,
    locked: Bool = false,
    composition: () -> SCNNode
  ) {
    let root = SCNNode()
    root.name = HubScene.buildingPrefix + id
    root.position = SCNVector3(Float(position.x), 0, Float(position.z))
    root.addChildNode(composition())

    let labelNode = SceneKitSupport.billboardText(
      label, size: 40, color: SceneKitSupport.uiColor(hex: HubHex.label))
    labelNode.position = SCNVector3(0, 3.4, 0)
    root.addChildNode(labelNode)

    let accent = SCNNode(geometry: SCNTorus(ringRadius: 0.9, pipeRadius: 0.06))
    accent.geometry?.materials = [SceneKitSupport.glowMaterial(hex: accentHex, intensity: locked ? 0.5 : 1.5)]
    accent.position = SCNVector3(0, 0.1, 0)
    accent.eulerAngles.x = -.pi / 2
    root.addChildNode(accent)

    if locked {
      dimmed(root)
    } else {
      let up = SCNAction.fadeOpacity(to: 1, duration: 1.2)
      let down = SCNAction.fadeOpacity(to: 0.45, duration: 1.2)
      for action in [up, down] {
        action.timingMode = .easeInEaseOut
      }
      accent.runAction(.repeatForever(.sequence([down, up])))
    }

    scene.rootNode.addChildNode(root)
  }

  /// 60% opacity across every material of the subtree.
  private func dimmed(_ node: SCNNode) {
    node.enumerateHierarchy { child, _ in
      child.opacity = 0.6
      for material in child.geometry?.materials ?? [] {
        material.transparency = 0.6
      }
    }
  }

  private func stone(at hex: UInt32) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .lambert
    material.diffuse.contents = SceneKitSupport.uiColor(hex: hex)
    return material
  }

  private func box(width: CGFloat, height: CGFloat, length: CGFloat, material: SCNMaterial) -> SCNNode {
    let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: 0)
    geometry.materials = [material]
    return SCNNode(geometry: geometry)
  }

  private func cylinder(radius: CGFloat, height: CGFloat, material: SCNMaterial) -> SCNNode {
    let geometry = SCNCylinder(radiusTop: radius, radiusBottom: radius, height: height)
    geometry.radialSegmentCount = 20
    geometry.materials = [material]
    return SCNNode(geometry: geometry)
  }

  private func cone(radius: CGFloat, height: CGFloat, material: SCNMaterial) -> SCNNode {
    let geometry = SCNCone(radiusTop: 0, radiusBottom: radius, height: height)
    geometry.radialSegmentCount = 20
    geometry.materials = [material]
    return SCNNode(geometry: geometry)
  }

  private func glowBox(size: CGFloat, hex: UInt32) -> SCNNode {
    let geometry = SCNBox(width: size, height: size, length: size, chamferRadius: 0)
    geometry.materials = [SceneKitSupport.glowMaterial(hex: hex, intensity: 1.4)]
    return SCNNode(geometry: geometry)
  }

  // MARK: - Compositions

  /// Torus arch upright over a flat stone base.
  private func portalComposition() -> SCNNode {
    let root = SCNNode()
    let base = box(width: 2.6, height: 0.3, length: 1.2, material: stone(at: HubHex.stoneDark))
    base.position = SCNVector3(0, 0.15, 0)
    root.addChildNode(base)

    let arch = SCNNode(geometry: SCNTorus(ringRadius: 1.4, pipeRadius: 0.18))
    arch.geometry?.materials = [stone(at: HubHex.stone)]
    arch.position = SCNVector3(0, 1.4, 0)
    arch.eulerAngles.x = .pi / 2 // stand the torus upright
    root.addChildNode(arch)
    return root
  }

  /// Box house + cone roof + chimney box, cool blue windows.
  private func tavernComposition() -> SCNNode {
    let root = SCNNode()
    let body = box(width: 1.4, height: 1.2, length: 1.4, material: stone(at: HubHex.stone))
    body.position = SCNVector3(0, 0.6, 0)
    root.addChildNode(body)

    let roof = cone(radius: 1.15, height: 0.9, material: stone(at: HubHex.wood))
    roof.position = SCNVector3(0, 1.65, 0)
    root.addChildNode(roof)

    let chimney = box(width: 0.22, height: 0.5, length: 0.22, material: stone(at: HubHex.stoneDark))
    chimney.position = SCNVector3(0.45, 2.0, 0)
    root.addChildNode(chimney)

    addWindows(hex: 0x4FC3F7, positions: [(-0.4, 0.7, 0.71), (0.4, 0.7, 0.71)], to: root)
    return root
  }

  /// Forge block + cylinder chimney + glowing ember cube in the mouth.
  private func forgeComposition() -> SCNNode {
    let root = SCNNode()
    let body = box(width: 1.5, height: 1.0, length: 1.2, material: stone(at: HubHex.stoneDark))
    body.position = SCNVector3(0, 0.5, 0)
    root.addChildNode(body)

    let chimney = cylinder(radius: 0.16, height: 1.0, material: stone(at: HubHex.stone))
    chimney.position = SCNVector3(-0.5, 1.4, 0)
    root.addChildNode(chimney)

    let ember = glowBox(size: 0.28, hex: 0xFF7A2A)
    ember.position = SCNVector3(0, 0.45, 0.62)
    root.addChildNode(ember)
    return root
  }

  /// Counter box + four thin legs + tilted awning plane, gold trim.
  private func merchantComposition() -> SCNNode {
    let root = SCNNode()
    let counter = box(width: 1.5, height: 0.7, length: 0.8, material: stone(at: HubHex.wood))
    counter.position = SCNVector3(0, 0.55, 0)
    root.addChildNode(counter)

    for legX: Float in [-0.65, 0.65] {
      for legZ: Float in [-0.3, 0.3] {
        let leg = cylinder(radius: 0.05, height: 1.7, material: stone(at: HubHex.wood))
        leg.position = SCNVector3(legX, 0.85, legZ)
        root.addChildNode(leg)
      }
    }

    let awning = SCNPlane(width: 1.7, height: 1.0)
    awning.materials = [stone(at: 0xC9584A)]
    awning.isDoubleSided = true
    let awningNode = SCNNode(geometry: awning)
    awningNode.position = SCNVector3(0, 1.75, -0.1)
    awningNode.eulerAngles.x = .pi / 3 // tilt toward the counter
    root.addChildNode(awningNode)
    return root
  }

  /// Two pillars + lintel.
  private func arenaGateComposition() -> SCNNode {
    let root = SCNNode()
    for pillarX: Float in [-0.9, 0.9] {
      let pillar = box(width: 0.35, height: 2.0, length: 0.35, material: stone(at: HubHex.stone))
      pillar.position = SCNVector3(pillarX, 1.0, 0)
      root.addChildNode(pillar)
    }
    let lintel = box(width: 2.3, height: 0.3, length: 0.4, material: stone(at: HubHex.stoneDark))
    lintel.position = SCNVector3(0, 2.15, 0)
    root.addChildNode(lintel)
    return root
  }

  /// Tall cylinder + cone top.
  private func towerComposition() -> SCNNode {
    let root = SCNNode()
    let body = cylinder(radius: 0.55, height: 2.8, material: stone(at: HubHex.stone))
    body.position = SCNVector3(0, 1.4, 0)
    root.addChildNode(body)

    let top = cone(radius: 0.7, height: 0.8, material: stone(at: HubHex.stoneDark))
    top.position = SCNVector3(0, 3.2, 0)
    root.addChildNode(top)
    return root
  }

  /// Wide hall + prism (rotated box) roof.
  private func guildHallComposition() -> SCNNode {
    let root = SCNNode()
    let body = box(width: 2.2, height: 1.1, length: 1.4, material: stone(at: HubHex.stone))
    body.position = SCNVector3(0, 0.55, 0)
    root.addChildNode(body)

    let roof = box(width: 1.2, height: 1.2, length: 1.5, material: stone(at: HubHex.wood))
    roof.position = SCNVector3(0, 1.55, 0)
    roof.eulerAngles.z = .pi / 4 // diamond cross-section reads as a prism roof
    root.addChildNode(roof)
    return root
  }

  private func addWindows(hex: UInt32, positions: [(Float, Float, Float)], to root: SCNNode) {
    for position in positions {
      let window = glowBox(size: 0.18, hex: hex)
      window.position = SCNVector3(position.0, position.1, position.2)
      root.addChildNode(window)
    }
  }
}
