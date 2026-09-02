import Foundation

/// Deterministic wind gusts. The app layer converts a Gust into a physics
/// force; GameCore only schedules and sizes them so runs are reproducible.
public struct WindSystem: Sendable {
  public enum Direction: String, Codable, Sendable, CaseIterable {
    case north, south, east, west
  }

  public struct Gust: Equatable, Codable, Sendable {
    public let startTick: UInt64
    public let durationTicks: UInt64
    /// 0.2…1.0
    public let strength: Double
    public let direction: Direction
  }

  private var generator: SeededGenerator

  public init(seed: UInt64) {
    generator = SeededGenerator(seed: seed)
  }

  public mutating func gust(afterTick tick: UInt64) -> Gust {
    let lead = UInt64.random(in: 8...20, using: &generator)
    let duration = UInt64.random(in: 3...8, using: &generator)
    let strength = Double.random(in: 0.2...1.0, using: &generator)
    let direction = Direction.allCases.randomElement(using: &generator)!
    return Gust(startTick: tick + lead, durationTicks: duration, strength: strength, direction: direction)
  }
}
