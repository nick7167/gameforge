import GameCore
import SwiftUI

/// Summon tab (spec §6.2): banner carousel, visible pity meters, gem-costed
/// pulls, the daily free summon, and the ritual reveal overlay.
@MainActor
struct SummonView: View {
  @ObservedObject var model: EmberGameModel

  /// Static v1 featured hero; weekly rotation comes from remote config (Plan 3).
  static let featuredHero = HeroCatalog.hero(id: "pyrelord")!

  @State private var revealVisible = false
  @State private var revealItems: [GachaEngine.PullResult] = []
  @State private var showRates = false

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        header
        bannerCarousel
        pityPanel
        summonButtons
        freePullButton
      }
      .padding(.horizontal, 16)
      .padding(.top, 70)
      .padding(.bottom, 110)
    }
    .fullScreenCover(isPresented: $revealVisible) {
      SummonRevealView(items: revealItems, onDismiss: { revealVisible = false })
    }
    .sheet(isPresented: $showRates) {
      RatesSheet()
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("Summon")
        .font(.system(size: 28, weight: .heavy, design: .rounded))
        .foregroundColor(DS.goldLight)
      Spacer()
      Button {
        showRates = true
      } label: {
        Image(systemName: "info.circle")
          .font(.system(size: 18, weight: .bold))
          .foregroundColor(DS.textSecondary)
      }
    }
  }

  // MARK: - Banner carousel

  private var bannerCarousel: some View {
    TabView {
      PermanentBannerCard()
      FeaturedBannerCard(featured: Self.featuredHero)
    }
    .tabViewStyle(.page(indexDisplayMode: .automatic))
    .frame(height: 180)
  }

  // MARK: - Pity meters

  private var pityPanel: some View {
    OrnatePanel {
      VStack(spacing: 12) {
        PityMeter(
          label: "Epic guarantee",
          value: model.profile.gacha.epicPity,
          limit: GachaEngine.epicPityLimit)
        PityMeter(
          label: "Legendary guarantee",
          value: model.profile.gacha.legendaryPity,
          limit: GachaEngine.legendaryPityLimit)
      }
    }
  }

  // MARK: - Summon buttons

  private var gems: Int { model.profile.wallet.balance(of: .gems) }

  private var summonButtons: some View {
    HStack(spacing: 12) {
      GoldButton(
        title: "×1 — \(GachaEngine.singleCost) 💎",
        style: gems >= GachaEngine.singleCost ? .gem : .disabled
      ) {
        performSummon(banner: .permanent, count: 1)
      }
      GoldButton(
        title: "×10 — \(GachaEngine.multiCost) 💎",
        style: gems >= GachaEngine.multiCost ? .gem : .disabled
      ) {
        performSummon(banner: .permanent, count: 10)
      }
    }
  }

  private var freePullButton: some View {
    GoldButton(
      title: model.freeSummonAvailable ? "FREE DAILY SUMMON" : "FREE PULL USED TODAY",
      style: model.freeSummonAvailable ? .gold : .disabled
    ) {
      performFreeSummon()
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - Actions

  private func performSummon(banner: GachaEngine.BannerKind, count: Int) {
    model.summon(banner: banner, count: count)
    presentReveal()
  }

  private func performFreeSummon() {
    guard model.freeDailySummon() else { return }
    presentReveal()
  }

  /// Move the model's results into the reveal overlay and clear them.
  private func presentReveal() {
    guard let results = model.lastSummonResults, !results.isEmpty else { return }
    revealItems = results
    revealVisible = true
    model.consumeSummonResults()
  }
}

// MARK: - Banner cards

/// Permanent pool card: "Everburning Portal", all 20 heroes.
private struct PermanentBannerCard: View {
  var body: some View {
    OrnatePanel {
      HStack(spacing: 14) {
        BannerSilhouette(initial: "✦", faction: .ember, rarity: .legendary)
        VStack(alignment: .leading, spacing: 6) {
          Text("Everburning Portal")
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundColor(DS.goldLight)
          Text("All 20 heroes")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(DS.textSecondary)
          factionGlyphRow
          Text("Legendary 2% · Epic 10%")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(DS.textSecondary)
        }
        Spacer()
      }
    }
    .frame(height: 180)
  }

  private var factionGlyphRow: some View {
    HStack(spacing: 8) {
      ForEach(Faction.allCases, id: \.self) { faction in
        Text(Self.glyph(faction))
          .font(.system(size: 14))
      }
    }
  }

  static func glyph(_ faction: Faction) -> String {
    switch faction {
    case .ember: return "🔥"
    case .frost: return "❄️"
    case .verdant: return "🌿"
    case .void: return "🌑"
    }
  }
}

/// Featured banner card: rate-up legendary, 4% legendary rate.
private struct FeaturedBannerCard: View {
  let featured: HeroDefinition

  var body: some View {
    OrnatePanel {
      HStack(spacing: 14) {
        BannerSilhouette(initial: String(featured.name.first ?? "?"), faction: featured.faction, rarity: featured.rarity)
        VStack(alignment: .leading, spacing: 6) {
          Text(featured.name)
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundColor(DS.goldLight)
          Text("RATE UP ★")
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundColor(DS.emberDark)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(DS.goldMid))
          Text("Legendary rate 4%")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(DS.textSecondary)
        }
        Spacer()
      }
    }
    .frame(height: 180)
  }
}

/// Rarity-framed hero silhouette placeholder: initial in a faction gradient.
struct BannerSilhouette: View {
  let initial: String
  let faction: Faction
  let rarity: Rarity

  var body: some View {
    RarityFrame(rarity: rarity) {
      RoundedRectangle(cornerRadius: 8)
        .fill(
          LinearGradient(
            colors: [DS.factionColor(faction).opacity(0.75), DS.panelDark],
            startPoint: .top, endPoint: .bottom))
        .overlay(
          Text(initial)
            .font(.system(size: 34, weight: .black, design: .rounded))
            .foregroundColor(.white.opacity(0.9)))
        .frame(width: 64, height: 96)
    }
  }
}

// MARK: - Pity meter

/// One horizontal pity progress bar: gold fill on a dark track with an X/Y counter.
private struct PityMeter: View {
  let label: String
  let value: Int
  let limit: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(label)
          .font(.system(size: 12, weight: .bold, design: .rounded))
          .foregroundColor(DS.textSecondary)
        Spacer()
        Text("\(min(value, limit))/\(limit)")
          .font(.system(size: 12, weight: .heavy, design: .rounded))
          .foregroundColor(DS.goldLight)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.black.opacity(0.5))
          Capsule()
            .fill(
              LinearGradient(colors: [DS.goldLight, DS.goldMid], startPoint: .leading, endPoint: .trailing))
            .frame(width: max(0, proxy.size.width * CGFloat(value) / CGFloat(limit)))
        }
      }
      .frame(height: 8)
    }
  }
}

// MARK: - Rates sheet

/// Exact rate table (spec §6.2), shown from the ⓘ button.
private struct RatesSheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      DS.emberDark.ignoresSafeArea()
      ScrollView {
        OrnatePanel {
          VStack(alignment: .leading, spacing: 12) {
            Text("Summon Rates")
              .font(.system(size: 20, weight: .heavy, design: .rounded))
              .foregroundColor(DS.goldLight)
            rateRow("Legendary", "2%")
            rateRow("Epic", "10%")
            rateRow("Rare", "30%")
            rateRow("Common", "58%")
            Divider().overlay(DS.goldDeep.opacity(0.5))
            Text("Featured Banner")
              .font(.system(size: 15, weight: .heavy, design: .rounded))
              .foregroundColor(DS.goldLight)
            rateRow("Legendary", "4%")
            Text("50% of legendaries on a featured banner are the rate-up hero.")
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(DS.textSecondary)
            Divider().overlay(DS.goldDeep.opacity(0.5))
            Text("Pity")
              .font(.system(size: 15, weight: .heavy, design: .rounded))
              .foregroundColor(DS.goldLight)
            rateRow("Epic guarantee", "within 10 pulls")
            rateRow("Legendary guarantee", "within 60 pulls")
            Text("Pity counters carry over between banners and reset on hit.")
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(DS.textSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func rateRow(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundColor(DS.textPrimary)
      Spacer()
      Text(value)
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundColor(DS.goldLight)
    }
  }
}
