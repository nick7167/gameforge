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
