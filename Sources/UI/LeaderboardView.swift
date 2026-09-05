import SwiftUI
import GameCore

/// Custom ornate season leaderboard (spec §10). v1 shows a locally generated
/// deterministic rival field around the player; the global board goes live
/// with accounts in Plan 3.
struct LeaderboardView: View {
  @ObservedObject var model: EmberGameModel

  private let provider: any LeaderboardProviding

  init(model: EmberGameModel, provider: any LeaderboardProviding = LocalLeaderboardProvider()) {
    self.model = model
    self.provider = provider
  }

  private var entries: [LeaderboardEntry] {
    provider.entries(
      playerName: model.profile.name,
      playerStage: model.profile.bestStage,
      playerPower: model.squadPower())
  }

  var body: some View {
    let ranked = entries
    let playerIndex = ranked.firstIndex(where: \.isPlayer)
    ScrollView {
      VStack(spacing: 14) {
        header
        rankSummary(rank: (playerIndex ?? 0) + 1, total: ranked.count)
        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, entry in
          row(entry: entry, rank: index + 1)
        }
        seasonNote
      }
      .padding(16)
    }
  }

  // MARK: - Sections

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Leaderboard")
        .font(.system(size: 28, weight: .heavy, design: .rounded))
        .foregroundColor(DS.goldLight)
      Text("Season 1 · resets in \(Self.daysToNextMonday)d")
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundColor(DS.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func rankSummary(rank: Int, total: Int) -> some View {
    let percent = max(1, Int((Double(rank) / Double(max(total, 1)) * 100).rounded()))
    return OrnatePanel {
      HStack {
        Text("Your rank: #\(rank)")
          .font(.system(size: 16, weight: .heavy, design: .rounded))
          .foregroundColor(DS.goldLight)
        Spacer()
        Text("Top \(percent)%")
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundColor(DS.textSecondary)
      }
    }
  }

  private func row(entry: LeaderboardEntry, rank: Int) -> some View {
    let medal = rank == 1 ? "🥇" : rank == 2 ? "🥈" : rank == 3 ? "🥉" : nil
    return OrnatePanel {
      HStack(spacing: 12) {
        Text(medal ?? "\(rank)")
          .font(.system(size: medal != nil ? 24 : 15, weight: .heavy, design: .rounded))
          .foregroundColor(medal != nil ? DS.goldLight : DS.textSecondary)
          .frame(width: 40)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(entry.name)
              .font(.system(size: 15, weight: .bold, design: .rounded))
              .foregroundColor(entry.isPlayer ? DS.goldLight : DS.textPrimary)
              .lineLimit(1)
            if entry.isPlayer {
              Text("YOU")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundColor(DS.emberDark)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(DS.goldLight))
            }
          }
          Text("Stage \(entry.stage.display)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(DS.textSecondary)
        }
        Spacer()
        Text("\(entry.power.formatted()) ⚔️")
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundColor(DS.textPrimary)
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(DS.goldLight.opacity(entry.isPlayer ? 0.9 : 0), lineWidth: 2))
  }

  private var seasonNote: some View {
    Text("Season 1 — global leaderboard goes live with accounts (v1.1)")
      .font(.system(size: 11, weight: .semibold, design: .rounded))
      .foregroundColor(DS.textSecondary)
      .multilineTextAlignment(.center)
      .padding(.top, 4)
  }

  /// Whole days from now until the next Monday 00:00 (season reset v1).
  static var daysToNextMonday: Int {
    let calendar = Calendar.current
    let now = calendar.startOfDay(for: Date())
    guard let next = calendar.nextDate(
      after: now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)
    else { return 7 }
    return max(1, calendar.dateComponents([.day], from: now, to: next).day ?? 7)
  }
}

// MARK: - Data

struct LeaderboardEntry: Identifiable {
  let id = UUID()
  let name: String
  let stage: StageID
  let power: Int
  let isPlayer: Bool
}

protocol LeaderboardProviding: Sendable {
  func entries(playerName: String, playerStage: StageID, playerPower: Int) -> [LeaderboardEntry]
}

/// Deterministic rival field: 49 rivals seeded by the player's stage index, so
/// the board is stable within a season and the player sits mid-pack.
struct LocalLeaderboardProvider: LeaderboardProviding {
  static let names = [
    "Aldric", "Brannoc", "Cinderia", "Dralith", "Emberlyn", "Frostgar", "Grimwald",
    "Holloway", "Ignatius", "Jorveth", "Kaelith", "Lunaris", "Mordwyn", "Nyxara",
    "Orinvale", "Pyralis", "Quillon", "Ravenna", "Solbrin", "Thornwick", "Umbrix",
    "Vaelora", "Wraithon", "Xandrel", "Ysmelda", "Zephyrus", "Ashkar", "Brimstone",
    "Corvax", "Duskwarden", "Everflame", "Flintmark", "Galehart", "Hexenmoor",
    "Icetalon", "Jadefire", "Krumholt", "Loreweaver", "Mistral", "Nightgale"
  ]

  func entries(playerName: String, playerStage: StageID, playerPower: Int) -> [LeaderboardEntry] {
    let seed = UInt64(bitPattern: Int64(playerStage.totalIndex))
    var rng = SeededGenerator(seed: seed &+ 0x5EED_BEEF)
    var rivals: [LeaderboardEntry] = []
    for offset in -24...24 where offset != 0 {
      let index = playerStage.totalIndex + offset
      guard index >= 1 else { continue }
      let stage = StageID(chapter: (index - 1) / 10 + 1, stage: (index - 1) % 10 + 1)
      let name = Self.names[abs((index * 7) % Self.names.count)]
      let power = basePower(for: stage, rng: &rng)
      rivals.append(LeaderboardEntry(name: name, stage: stage, power: power, isPlayer: false))
    }
    let player = LeaderboardEntry(
      name: playerName, stage: playerStage, power: playerPower, isPlayer: true)
    let all = (rivals + [player]).sorted { lhs, rhs in
      lhs.stage.totalIndex != rhs.stage.totalIndex
        ? lhs.stage.totalIndex > rhs.stage.totalIndex
        : lhs.power > rhs.power
    }
    return Array(all.prefix(50))
  }

  /// Power consistent with a stage: the same curve as stage rewards.
  private func basePower(for stage: StageID, rng: inout SeededGenerator) -> Int {
    let base = Int(900 * pow(1.18, Double(stage.totalIndex - 1)))
    return base + Int(rng.next() % UInt64(max(base / 5, 1)))
  }
}
