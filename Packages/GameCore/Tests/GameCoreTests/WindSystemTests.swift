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
      let gust = wind.gust(afterTick: tick)
      #expect(gust.durationTicks >= 3 && gust.durationTicks <= 8)
      #expect(gust.strength >= 0.2 && gust.strength <= 1.0)
      tick = gust.startTick + gust.durationTicks
    }
  }

  @Test func gustStartsAfterLeadTime() {
    var wind = WindSystem(seed: 7)
    let gust = wind.gust(afterTick: 100)
    #expect(gust.startTick > 100)
  }
}
