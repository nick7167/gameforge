import Testing
@testable import GameCore

@Suite struct WindSystemTests {
  @Test func deterministicForSameSeed() {
    var a = WindSystem(seed: 42)
    var b = WindSystem(seed: 42)
    let ga = a.gust(afterTick: 0)
    let gb = b.gust(afterTick: 0)
    #expect(ga == gb)
  }

  @Test func differentSeedsDiffer() {
    var a = WindSystem(seed: 1)
    var b = WindSystem(seed: 2)
    // Fixed seeds chosen to differ; not a hard mathematical guarantee.
    #expect(a.gust(afterTick: 0) != b.gust(afterTick: 0))
  }

  @Test func gustFieldsInBounds() {
    var wind = WindSystem(seed: 42)
    var tick: UInt64 = 0
    for _ in 0..<50 {
      let g = wind.gust(afterTick: tick)
      #expect(g.durationTicks >= 3 && g.durationTicks <= 8)
      #expect(g.strength >= 0.2 && g.strength <= 1.0)
      tick = g.startTick + g.durationTicks
    }
  }

  @Test func gustStartsAfterLeadTime() {
    var wind = WindSystem(seed: 7)
    let g = wind.gust(afterTick: 100)
    #expect(g.startTick > 100)
  }
}