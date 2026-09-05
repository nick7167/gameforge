import SwiftUI
import GameCore

/// Quests screen (spec §9): daily / weekly / achievement tabs with progress
/// bars and claim buttons. Rewards are claimed through the model.
struct QuestsView: View {
  enum QuestTab: String, CaseIterable {
    case daily = "Daily", weekly = "Weekly", achievements = "Achievements"

    var quests: [QuestDefinition] {
      switch self {
      case .daily: QuestSystem.dailies
      case .weekly: QuestSystem.weeklies
      case .achievements: QuestSystem.achievements
      }
    }
  }

  @ObservedObject var model: EmberGameModel
  @State private var selectedTab: QuestTab = .daily

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        header
        tabChips
        claimAllButton
        ForEach(selectedTab.quests) { quest in
          questRow(quest)
        }
      }
      .padding(16)
    }
  }

  // MARK: - Sections

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Quests")
        .font(.system(size: 28, weight: .heavy, design: .rounded))
        .foregroundColor(DS.goldLight)
      Text("Complete tasks, earn gems & tokens")
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundColor(DS.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var tabChips: some View {
    HStack(spacing: 8) {
      ForEach(QuestTab.allCases, id: \.self) { tab in
        let selected = selectedTab == tab
        Button {
          selectedTab = tab
        } label: {
          Text(tab.rawValue)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundColor(selected ? DS.emberDark : DS.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
              Capsule().fill(selected ? AnyShapeStyle(DS.goldLight) : AnyShapeStyle(DS.panelLight)))
            .overlay(Capsule().strokeBorder(DS.goldDeep.opacity(selected ? 0 : 0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
  }

  @ViewBuilder
  private var claimAllButton: some View {
    if claimableCount > 0 {
      GoldButton(title: "Claim All (\(claimableCount))", style: .gold) {
        _ = model.claimQuests(selectedTab.quests)
      }
    }
  }

  private var claimableCount: Int {
    selectedTab.quests.filter { quest in
      guard let progress = model.profile.quests.progress(for: quest.id) else { return false }
      return !progress.claimed && progress.count >= quest.goal
    }.count
  }

  // MARK: - Rows

  private func questRow(_ quest: QuestDefinition) -> some View {
    let progress = model.profile.quests.progress(for: quest.id)
    let count = progress?.count ?? 0
    let claimed = progress?.claimed ?? false
    let complete = count >= quest.goal
    return OrnatePanel {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(quest.title)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(DS.textPrimary)
          Spacer()
          Text(rewardLine(quest))
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(DS.goldLight)
        }
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            Capsule().fill(Color.black.opacity(0.4))
            Capsule()
              .fill(LinearGradient(colors: [DS.goldLight, DS.goldMid], startPoint: .leading, endPoint: .trailing))
              .frame(width: geometry.size.width * min(1, Double(count) / Double(quest.goal)))
          }
        }
        .frame(height: 8)
        HStack {
          if claimed {
            Text("Claimed ✓")
              .font(.system(size: 12, weight: .heavy, design: .rounded))
              .foregroundColor(DS.textSecondary)
          } else if complete {
            GoldButton(title: "CLAIM", style: .gold) {
              _ = model.claimQuest(questID: quest.id)
            }
          } else {
            Text("\(min(count, quest.goal).formatted()) / \(quest.goal.formatted())")
              .font(.system(size: 12, weight: .semibold, design: .rounded))
              .foregroundColor(DS.textSecondary)
          }
          Spacer()
        }
      }
    }
  }

  private func rewardLine(_ quest: QuestDefinition) -> String {
    var parts: [String] = []
    if quest.rewardGems > 0 { parts.append("💎 \(quest.rewardGems)") }
    if quest.rewardQuestTokens > 0 { parts.append("🎫 \(quest.rewardQuestTokens)") }
    return parts.joined(separator: " · ")
  }
}
