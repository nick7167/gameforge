import Foundation
import Testing
@testable import GameCore

struct SeededGeneratorTests {
    @Test func sameSeedProducesSameSequence() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        let first = (0..<16).map { _ in a.next() }
        let second = (0..<16).map { _ in b.next() }
        #expect(first == second)
    }

    @Test func differentSeedsProduceDifferentSequences() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        #expect(a.next() != b.next())
    }

    @Test func valuesAreWithinFullRange() {
        var rng = SeededGenerator(seed: 7)
        let values = (0..<1000).map { _ in rng.next() }
        #expect(Set(values).count == 1000)
    }
}

struct SessionTests {
    @Test func startResetsScoreAndBeginsPlaying() {
        var session = Session(bestScore: 10)
        session.start()
        session.addScore(5)
        session.finish()
        session.start()
        #expect(session.score == 0)
        #expect(session.phase == .playing)
    }

    @Test func finishUpdatesBestScore() {
        var session = Session(bestScore: 10)
        session.start()
        session.addScore(25)
        session.finish()
        #expect(session.bestScore == 25)
        #expect(session.phase == .finished)
    }

    @Test func bestScoreNeverDecreases() {
        var session = Session(bestScore: 50)
        session.start()
        session.addScore(5)
        session.finish()
        #expect(session.bestScore == 50)
    }

    @Test func pauseOnlyWorksWhilePlaying() {
        var session = Session()
        session.pause()
        #expect(session.phase == .menu)
        session.start()
        session.pause()
        #expect(session.phase == .paused)
        session.resume()
        #expect(session.phase == .playing)
    }

    @Test func stateSnapshotRoundtripsThroughCodable() throws {
        var session = Session(bestScore: 12)
        session.start()
        session.addScore(34)
        session.finish()

        let data = try JSONEncoder().encode(session.state)
        let decoded = try JSONDecoder().decode(SessionState.self, from: data)
        let restored = Session(state: decoded)
        #expect(restored.state == session.state)
    }
}

struct HighScoreStoreTests {
    @Test func recordReturnsTrueOnlyForNewBest() {
        let store = InMemoryHighScoreStore()
        #expect(store.record(score: 10, for: "demo"))
        #expect(!store.record(score: 5, for: "demo"))
        #expect(store.record(score: 20, for: "demo"))
        #expect(store.bestScore(for: "demo") == 20)
    }

    @Test func unknownGameReturnsZero() {
        let store = InMemoryHighScoreStore()
        #expect(store.bestScore(for: "nope") == 0)
    }
}
