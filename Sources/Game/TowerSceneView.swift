import SwiftUI
import SceneKit

/// Bridges the SceneKit scene into SwiftUI and drives the per-frame game
/// loop. `onFrame` fires every rendered frame on the main actor — this is
/// what makes the block slide, wind blow, and collapses register.
struct TowerSceneView: UIViewRepresentable {
  let scene: TowerScene
  var onFrame: (() -> Void)?

  func makeUIView(context: Context) -> SCNView {
    let view = SCNView()
    view.scene = scene
    view.backgroundColor = .clear
    view.antialiasingMode = .multisampling2X
    view.preferredFramesPerSecond = 60
    view.isJitteringEnabled = true
    // Keep the render loop running even when the scene has no animations —
    // otherwise renderer(updateAtTime:) never fires and the game is frozen.
    view.isPlaying = true
    view.delegate = context.coordinator
    return view
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onFrame: onFrame)
  }

  func updateUIView(_ uiView: SCNView, context: Context) {
    context.coordinator.onFrame = onFrame
  }

  final class Coordinator: NSObject, SCNSceneRendererDelegate {
    var onFrame: (() -> Void)?

    init(onFrame: (() -> Void)?) {
      self.onFrame = onFrame
    }

    // The renderer callback fires on a render thread; hop to the main actor
    // before touching game state (Swift 6 isolation).
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
      DispatchQueue.main.async { [weak self] in
        self?.onFrame?()
      }
    }
  }
}
