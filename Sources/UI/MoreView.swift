import SwiftUI
import GameCore

/// "More" tab hub: a 2-column grid of ornate tiles opening each sub-screen
/// (leaderboard, quests, profile, mail, settings) via full-screen covers.
struct MoreView: View {
  @ObservedObject var model: EmberGameModel
  @ObservedObject var purchaseService: PurchaseService

  private enum Sheet: String, Identifiable {
    case leaderboard, quests, profile, mail, settings
    var id: String { rawValue }
  }

  @State private var activeSheet: Sheet?

  private struct Tile: Identifiable {
    let sheet: Sheet
    let glyph: String
    let label: String
    let subtitle: String
    var id: String { sheet.rawValue }
  }

  private static let tiles: [Tile] = [
    Tile(sheet: .leaderboard, glyph: "🏆", label: "Leaderboard", subtitle: "Season 1 rankings"),
    Tile(sheet: .quests, glyph: "📜", label: "Quests", subtitle: "Dailies & rewards"),
    Tile(sheet: .profile, glyph: "👤", label: "Profile", subtitle: "Your legend"),
    Tile(sheet: .mail, glyph: "📥", label: "Mail", subtitle: "Rewards inbox"),
    Tile(sheet: .settings, glyph: "⚙️", label: "Settings", subtitle: "Audio & account")
  ]

  private let columns = [
    GridItem(.flexible(), spacing: 14),
    GridItem(.flexible(), spacing: 14)
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        LazyVGrid(columns: columns, spacing: 14) {
          ForEach(Self.tiles) { tile in
            tileCard(tile)
          }
        }
      }
      .padding(16)
    }
    .fullScreenCover(item: $activeSheet) { sheet in
      NavigationStack { destination(for: sheet) }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("More")
        .font(.system(size: 28, weight: .heavy, design: .rounded))
        .foregroundColor(DS.goldLight)
      Text("Everything else in the realm")
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundColor(DS.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func tileCard(_ tile: Tile) -> some View {
    Button {
      activeSheet = tile.sheet
    } label: {
      OrnatePanel {
        VStack(spacing: 10) {
          Text(tile.glyph)
            .font(.system(size: 44))
          Text(tile.label)
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundColor(DS.textPrimary)
          Text(tile.subtitle)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(DS.textSecondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func destination(for sheet: Sheet) -> some View {
    switch sheet {
    case .leaderboard:
      LeaderboardView(model: model)
    case .quests:
      QuestsView(model: model)
    case .profile:
      ProfileView(model: model)
    case .mail:
      MailView()
    case .settings:
      SettingsView(model: model, purchaseService: purchaseService)
    }
  }
}

/// Mail inbox placeholder (full backend lands in Plan 3).
private struct MailView: View {
  var body: some View {
    OrnatePanel {
      VStack(spacing: 10) {
        Text("📥")
          .font(.system(size: 48))
        Text("No mail")
          .font(.system(size: 18, weight: .heavy, design: .rounded))
          .foregroundColor(DS.textPrimary)
        Text("Check back after the next update")
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundColor(DS.textSecondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 30)
    }
    .padding(16)
  }
}
