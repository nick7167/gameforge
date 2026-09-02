import Testing
import Foundation
@testable import GameCore

@Suite struct DailyChallengeTests {
  var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }

  let day = Date(timeIntervalSince1970: 1_700_000_000)

  @Test func sameDateSameChallenge() {
    let a = DailyChallenge(date: day, calendar: calendar)
    let b = DailyChallenge(date: day, calendar: calendar)
    #expect(a.seed == b.seed)
    #expect(a.allowedTypeIDs == b.allowedTypeIDs)
    #expect(a.targetHeight == b.targetHeight)
  }

  @Test func differentDatesDiffer() {
    let next = day.addingTimeInterval(86_400)
    let a = DailyChallenge(date: day, calendar: calendar)
    let b = DailyChallenge(date: next, calendar: calendar)
    #expect(a.seed != b.seed)
  }

  @Test func allowedTypesInCatalog() {
    let challenge = DailyChallenge(date: day, calendar: calendar)
    let catalogIDs = Set(DistrictType.v1Catalog.map(\.id))
    #expect(challenge.allowedTypeIDs.count >= 3 && challenge.allowedTypeIDs.count <= 5)
    #expect(challenge.allowedTypeIDs.isSubset(of: catalogIDs))
  }

  @Test func targetHeightReasonable() {
    let challenge = DailyChallenge(date: day, calendar: calendar)
    #expect(challenge.targetHeight >= 20 && challenge.targetHeight <= 60)
  }
}