import SpriteKit

/// Events a demo scene can report back to the app layer.
enum DemoGameEvent: Sendable {
    case scored(points: Int)
    case ended
}

/// A self-contained playable scene that proves the SpriteKit pipeline works
/// end to end: physics, touch input, scoring, and event bridging to SwiftUI.
///
/// Tap anywhere to spawn a bouncing ball. Each ball scores a point; the
/// "End" button finishes the round.
@MainActor
final class DemoScene: SKScene {
    var onEvent: ((DemoGameEvent) -> Void)?

    private var hasReportedEnd = false

    private let scoreNode = SKLabelNode(fontNamed: "SFPro-Bold")

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = SKColor(red: 0.10, green: 0.11, blue: 0.20, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -2.2)
        addTitle()
        addEndButton()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DemoScene is created in code, not from a scene archive")
    }

    private func addTitle() {
        scoreNode.text = "GameForge — tap to spawn"
        scoreNode.fontSize = 32
        scoreNode.fontColor = .white
        scoreNode.position = CGPoint(x: size.width / 2, y: size.height - 140)
        addChild(scoreNode)
    }

    private func addEndButton() {
        let button = SKLabelNode(fontNamed: "SFPro-Medium")
        button.name = "endButton"
        button.text = "End round"
        button.fontSize = 24
        button.fontColor = SKColor(white: 0.85, alpha: 1)
        button.position = CGPoint(x: size.width / 2, y: 90)
        addChild(button)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self) else { return }
        let node = atPoint(location)
        if node.name == "endButton" {
            endRound()
            return
        }
        spawnBall(at: location)
    }

    /// Spawns a ball without touch input; used by smoke tests and previews.
    func spawnForTesting() {
        spawnBall(at: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    private func spawnBall(at position: CGPoint) {
        let radius = CGFloat.random(in: 18...36)
        let ball = SKShapeNode(circleOfRadius: radius)
        ball.fillColor = SKColor(
            hue: .random(in: 0...1),
            saturation: 0.75,
            brightness: 0.95,
            alpha: 1
        )
        ball.strokeColor = .clear
        ball.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        ball.physicsBody?.restitution = 0.75
        ball.position = position
        addChild(ball)

        onEvent?(.scored(points: 1))
    }

    private func endRound() {
        guard !hasReportedEnd else { return }
        hasReportedEnd = true
        onEvent?(.ended)
    }
}
