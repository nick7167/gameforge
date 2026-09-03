import SwiftUI
import SceneKit

/// Bridges the SceneKit scene into SwiftUI and drives the per-frame game
/// loop. `onFrame` fires every rendered frame on the main actor — this is
/// what makes the block slide, wind blow, and collapses register.
struct TowerSceneView: UIViewRepresentable {
  let scene: TowerScene
  var onFrame: (() -> Void)?
  var onTap: (() -> Void)?

  func makeUIView(context: Context) -> SCNView {
    let view = SCNView()
    view.scene = scene
    view.backgroundColor = .clear
    // Required for the SwiftUI gradient behind to show through — an opaque
    // SCNView with a clear color renders BLACK, hiding the 3D content.
    view.isOpaque = false
    view.antialiasingMode = .multisampling2X
    view.preferredFramesPerSecond = 60
    // Keep the render loop running even when the scene has no animations —
    // otherwise renderer(updateAtTime:) never fires and the game is frozen.
    view.isPlaying = true
    view.delegate = context.coordinator
    // Direct tap recognizer: bypasses SwiftUI gesture delay (the "laggy
    // taps" complaint) — drops land on the same frame the finger lands.
    let tap = UITapGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleTap)
    )
    view.addGestureRecognizer(tap)
    context.coordinator.onTap = onTap
    return view
  }

  func makeCoordinator() -> Coordinator {
    MainActor.assumeIsolated {
      Coordinator(onFrame: onFrame, onTap: onTap)
    }
  }

  func updateUIView(_ uiView: SCNView, context: Context) {
    MainActor.assumeIsolated {
      context.coordinator.onFrame = onFrame
      context.coordinator.onTap = onTap
    }
  }

  /// Main-actor isolated coordinator: the render loop is UI-adjacent, so all
  /// state lives on the main actor and Swift 6 isolation is satisfied.
  @MainActor
  final class Coordinator: NSObject, SCNSceneRendererDelegate {
    var onFrame: (() -> Void)?
    var onTap: (() -> Void)?

    init(onFrame: (() -> Void)?, onTap: (() -> Void)?) {
      self.onFrame = onFrame
      self.onTap = onTap
    }

    @objc func handleTap() {
      onTap?()
    }

    // The renderer callback fires on a render thread; hop to the main queue
    // (== main actor) before touching game state. DispatchQueue hop avoids
    // a Task allocation every frame (60/s) — the v26 lag complaint.
    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
      DispatchQueue.main.async { [weak self] in
        MainActor.assumeIsolated {
          self?.onFrame?()
        }
      }
    }
  }
}
