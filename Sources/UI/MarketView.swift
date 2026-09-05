import GameCore
import SwiftUI
import UIKit

/// In-game Market (spec §12): daily rotating stock across 4 tabs. All prices
/// are in-game currency — real-money purchases live in the Premium Shop.
struct MarketView: View {
  enum MarketTab: String, CaseIterable {
    case gold = "Gold", gems = "Gems", arena = "Arena", quests = "Quest"

    var icon: String {
      switch self {
      case .gold: "🪙"
      case .gems: "💎"
      case .arena: "⚔️"
      case .quests: "📜"
      }
    }
  }

  @ObservedObject var model: EmberGameModel
  @State private var selectedTab: MarketTab = .gold

  private var stock: [MarketEntry] { MarketSystem.dailyStock() }

  var body: some View {
    VStack(spacing: 0) {
      header
      tabChips
      ScrollView {
        VStack(spacing: 10) {
          switch selectedTab {
          case .gold, .gems:
            ForEach(entries) { entry in
              MarketEntryRow(
                entry: entry, affordable: isAffordable(entry),
                freeClaimed: model.freeMarketClaimedToday() && entry.price == 0
              ) {
                buy(entry)
              }
            }
          case .arena:
            lockedPanel(icon: "⚔️", title: "Arena opens soon", subtitle: "Spend Arena Tokens in v1.5")
          case .quests:
            lockedPanel(icon: "📜", title: "Coming soon", subtitle: "Quest Token shop arrives in v1.1")
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 110)
      }
    }
  }

  private var entries: [MarketEntry] {
    stock.filter { $0.currency == (selectedTab == .gold ? Currency.gold : Currency.gems) }
  }

  // MARK: - Header

  private var header: some View {
    VStack(spacing: 2) {
      Text("Market")
        .font(.system(size: 24, weight: .black, design: .rounded))
        .foregroundStyle(
          LinearGradient(colors: [DS.goldLight, DS.goldMid], startPoint: .top, endPoint: .bottom))
      Text("New stock in \(Self.timeUntilMidnight())")
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundColor(DS.textSecondary)
    }
    .padding(.top, 10)
  }

  /// Static compute on appear: "Xh Ym" until the next local midnight.
  static func timeUntilMidnight(now: Date = Date(), calendar: Calendar = .current) -> String {
    let startOfTomorrow = calendar.startOfDay(for: now).addingTimeInterval(86_400)
    let remaining = max(0, Int(startOfTomorrow.timeIntervalSince(now)))
    return String(format: "%dh %02dm", remaining / 3600, (remaining % 3600) / 60)
  }

  // MARK: - Tabs

  private var tabChips: some View {
    HStack(spacing: 8) {
      ForEach(MarketTab.allCases, id: \.self) { tab in
        let selected = selectedTab == tab
        Button {
          selectedTab = tab
        } label: {
          HStack(spacing: 4) {
            Text(tab.icon).font(.system(size: 12))
            Text(tab.rawValue)
              .font(.system(size: 12, weight: .bold, design: .rounded))
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(
            Capsule().fill(selected ? Color.black.opacity(0.55) : Color.black.opacity(0.25)))
          .overlay(
            Capsule().strokeBorder(selected ? DS.goldMid : DS.goldDeep.opacity(0.4), lineWidth: 1))
          .foregroundColor(selected ? DS.goldLight : DS.textSecondary)
        }
      }
    }
    .padding(.top, 10)
  }

  // MARK: - Buying

  private func isAffordable(_ entry: MarketEntry) -> Bool {
    entry.price == 0 || model.profile.wallet.balance(of: entry.currency) >= entry.price
  }

  private func buy(_ entry: MarketEntry) {
    guard model.buyMarket(entryID: entry.id) else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
  }

  // MARK: - Locked panels

  private func lockedPanel(icon: String, title: String, subtitle: String) -> some View {
    OrnatePanel {
      VStack(spacing: 6) {
        Text(icon).font(.system(size: 34))
        Text(title)
          .font(.system(size: 17, weight: .black, design: .rounded))
          .foregroundColor(DS.textPrimary)
        Text(subtitle)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(DS.textSecondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 18)
    }
    .opacity(0.75)
  }
}

/// One stock row: title/subtitle on the left, price chip + buy on the right.
private struct MarketEntryRow: View {
  let entry: MarketEntry
  let affordable: Bool
  let freeClaimed: Bool
  let onBuy: () -> Void

  private var buyEnabled: Bool { affordable && !freeClaimed }

  var body: some View {
    OrnatePanel {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text(entry.title)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundColor(DS.textPrimary)
          Text(entry.subtitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(DS.textSecondary)
        }
        Spacer()
        priceChip
        buyButton
      }
    }
  }

  private var priceChip: some View {
    Group {
      if entry.price == 0 {
        Text(freeClaimed ? "CLAIMED" : "FREE")
          .font(.system(size: 11, weight: .black, design: .rounded))
          .foregroundColor(freeClaimed ? DS.textSecondary : DS.goldLight)
      } else {
        HStack(spacing: 3) {
          Text(entry.currency == .gold ? "🪙" : "💎").font(.system(size: 11))
          Text(entry.price.formatted())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(affordable ? DS.textPrimary : Color(red: 1.0, green: 0.45, blue: 0.4))
        }
      }
    }
  }

  private var buyButton: some View {
    Button(action: onBuy) {
      Text("Buy")
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundColor(DS.emberDark)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
          Capsule().fill(
            LinearGradient(
              colors: buyEnabled ? [DS.goldLight, DS.goldMid] : [Color(white: 0.4), Color(white: 0.3)],
              startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
    }
    .disabled(!buyEnabled)
    .opacity(freeClaimed ? 0.5 : 1)
  }
}
