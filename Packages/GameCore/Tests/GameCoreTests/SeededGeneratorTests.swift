import Testing
@testable import GameCore

@Suite struct SeededGeneratorTests {
  @Test func generatesDeterministically() {
    var a = SeededGenerator(seed: 1)
    var b = SeededGenerator(seed: 1)
    #expect(a.next() == b.next())
  }

  @Test func differentSeedsDiverge() {
    var a = SeededGenerator(seed: 1)
    var b = SeededGenerator(seed: 2)
    #expect(a.next() != b.next())
  }
}
