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
    MainActor.assumeIsolated {
      Coordinator(onFrame: onFrame)
    }
  }

  func updateUIView(_ uiView: SCNView, context: Context) {
    MainActor.assumeIsolated {
      context.coordinator.onFrame = onFrame
    }
  }

  /// Main-actor isolated coordinator: the render loop is UI-adjacent, so all
  /// state lives on the main actor and Swift 6 isolation is satisfied.
  @MainActor
  final class Coordinator: NSObject, SCNSceneRendererDelegate {
    var onFrame: (() -> Void)?

    init(onFrame: (() -> Void)?) {
      self.onFrame = onFrame
    }

    // The renderer callback fires on a render thread; hop to the main actor
    // before touching game state.
    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
      Task { @MainActor [weak self] in
        self?.onFrame?()
      }
    }
  }
}
