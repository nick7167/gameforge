import Testing
@testable import GameCore

@Suite struct PlacementTests {
  let rules = PlacementRules()

  @Test func snapClampsToGrid() {
    #expect(rules.snap(GridPoint(x: 1, z: 1)) == GridPoint(x: 1, z: 1))
    #expect(rules.snap(GridPoint(x: 9, z: -9)) == GridPoint(x: 3, z: -3))
  }

  @Test func alignmentError() {
    #expect(rules.alignmentError(offset: GridPoint(x: 0, z: 0)) == 0)
    #expect(rules.alignmentError(offset: GridPoint(x: 3, z: 4)) == 5)
  }

  @Test func perfectPlacementThreshold() {
    // 0.15 cells in Euclidean distance: (0,0) perfect; (1,0) not.
    #expect(rules.alignmentError(offset: GridPoint(x: 0, z: 0)) <= PlacementRules.perfectThreshold)
    #expect(rules.alignmentError(offset: GridPoint(x: 1, z: 0)) > PlacementRules.perfectThreshold)
  }

  @Test func supportedWhenCentered() {
    let below = (footprint: 2, origin: GridPoint(x: 0, z: 0))
    #expect(rules.isSupported(footprint: 2, origin: GridPoint(x: 0, z: 0), belowFootprint: below.footprint, belowOrigin: below.origin))
  }

  @Test func unsupportedWhenNoOverlap() {
    let below = (footprint: 2, origin: GridPoint(x: 0, z: 0))
    #expect(!rules.isSupported(footprint: 2, origin: GridPoint(x: 3, z: 0), belowFootprint: below.footprint, belowOrigin: below.origin))
  }

  @Test func overhangLimit() {
    // footprint 2 at x=1 spans cells 0..1; below (x=0) spans -1..0 → overlap at cell 0, overhang 1 — allowed.
    let below = (footprint: 2, origin: GridPoint(x: 0, z: 0))
    #expect(rules.isSupported(footprint: 2, origin: GridPoint(x: 1, z: 0), belowFootprint: below.footprint, belowOrigin: below.origin))
    // footprint 2 at x=2 spans cells 1..2 → no overlap with below at all — not supported.
    #expect(!rules.isSupported(footprint: 2, origin: GridPoint(x: 2, z: 0), belowFootprint: below.footprint, belowOrigin: below.origin))
  }
}
