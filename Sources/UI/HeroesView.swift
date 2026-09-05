import GameCore
import SwiftUI

/// Heroes tab: squad power summary, 5-slot team editor strip, and an owned
/// hero grid. Tapping a grid hero opens HeroDetailView; tapping a grid hero
/// while a team slot is selected places/swaps that hero into the squad.
@MainActor
struct HeroesView: View {
  @ObservedObject var model: EmberGameModel

  enum SortMode: String, CaseIterable {
    case power = "Power", rarity = "Rarity", faction = "Faction"
  }

  @State private var selectedSlot: Int?
  @State private var sortMode: SortMode = .power
  @State private var detailHeroID: String?
  @State private var showDetail = false

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        header
        teamStrip
        sortPicker
        heroGrid
      }
      .padding(.horizontal, 16)
      .padding(.top, 70)
      .padding(.bottom, 110)
    }
    .fullScreenCover(isPresented: $showDetail) {
      if let detailHeroID {
        HeroDetailView(model: model, heroID: detailHeroID)
      }
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Heroes")
        .font(.system(size: 28, weight: .heavy, design: .rounded))
        .foregroundColor(DS.goldLight)
      Text("Squad Power \(squadPower)")
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundColor(DS.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var squadPower: Int { model.squadPower() }

  /// Combat power proxy: attack + defense + a tenth of HP.
  static func power(of hero: OwnedHero?) -> Int {
    guard let hero else { return 0 }
    let stats = hero.stats()
    return Int(stats.attack + stats.defense + stats.hp / 10)
  }

  // MARK: - Team editor strip

  private var teamStrip: some View {
    HStack(spacing: 12) {
      ForEach(0..<5, id: \.self) { slot in
        squadSlot(slot)
      }
    }
    .padding(12)
    .background(Capsule().fill(DS.panelDark.opacity(0.85)))
    .overlay(Capsule().strokeBorder(DS.goldDeep.opacity(0.6), lineWidth: 1))
  }

  @ViewBuilder
  private func squadSlot(_ slot: Int) -> some View {
    let hero = model.profile.ownedHeroes.first { $0.definitionID == model.profile.squad[slot] }
    Button {
      // Tap a filled slot: select it (or cancel if already selected).
      selectedSlot = selectedSlot == slot ? nil : slot
    } label: {
      if let hero, let def = HeroCatalog.hero(id: hero.definitionID) {
        HeroAvatar(definition: def, level: hero.level, diameter: 48)
      } else {
        Circle()
          .strokeBorder(DS.textSecondary.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4]))
          .frame(width: 48, height: 48)
      }
    }
    .overlay(alignment: .top) {
      if selectedSlot == slot {
        Image(systemName: "arrowtriangle.down.fill")
          .font(.system(size: 10))
          .foregroundColor(DS.goldLight)
          .offset(y: -10)
      }
    }
    .buttonStyle(.plain)
  }

  // MARK: - Sort picker

  private var sortPicker: some View {
    Picker("Sort", selection: $sortMode) {
      ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
    }
    .pickerStyle(.segmented)
    .frame(maxWidth: 260)
  }

  // MARK: - Hero grid

  private var sortedHeroes: [OwnedHero] {
    let heroes = model.profile.ownedHeroes
    switch sortMode {
    case .power:
      return heroes.sorted { Self.power(of: $0) > Self.power(of: $1) }
    case .rarity:
      return heroes.sorted { $0.rarityOrder > $1.rarityOrder }
    case .faction:
      return heroes.sorted { "\($0.definitionID)" < "\($1.definitionID)" }
    }
  }

  private var heroGrid: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104))], spacing: 12) {
      ForEach(sortedHeroes) { hero in
        heroCard(hero)
      }
    }
  }

  @ViewBuilder
  private func heroCard(_ hero: OwnedHero) -> some View {
    if let def = HeroCatalog.hero(id: hero.definitionID) {
      Button {
        handleGridTap(heroID: hero.definitionID)
      } label: {
        RarityFrame(rarity: def.rarity) {
          VStack(spacing: 4) {
            HeroAvatar(definition: def, level: hero.level, diameter: 56)
            Text(def.name)
              .font(.system(size: 12, weight: .bold, design: .rounded))
              .foregroundColor(DS.textPrimary)
              .lineLimit(1)
            Text(String(repeating: "★", count: max(1, hero.stars)))
              .font(.system(size: 10))
              .foregroundColor(DS.goldLight)
            Text(roleGlyph(def.role))
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(DS.factionColor(def.faction))
          }
          .padding(8)
        }
      }
      .buttonStyle(.plain)
    }
  }

  /// Grid tap is context-sensitive: place into the selected squad slot when
  /// one is active, otherwise open the hero detail. Tapping the hero already
  /// in the selected slot cancels selection (squads always hold 5 heroes).
  private func handleGridTap(heroID: String) {
    guard let slot = selectedSlot else {
      detailHeroID = heroID
      showDetail = true
      return
    }
    var squad = model.profile.squad
    if squad[slot] != heroID {
      if let existing = squad.firstIndex(of: heroID) {
        squad.swapAt(slot, existing) // swap with the slot the hero came from
      } else {
        squad[slot] = heroID
      }
      model.setSquad(squad)
    }
    selectedSlot = nil
  }

  private func roleGlyph(_ role: HeroRole) -> String {
    switch role {
    case .tank: return "🛡"
    case .dps: return "⚔️"
    case .healer: return "✚"
    case .support: return "✨"
    case .ranger: return "🏹"
    case .controller: return "🌀"
    case .assassin: return "🗡"
    }
  }
}

extension OwnedHero {
  /// Sort key for the rarity sort: legendary highest.
  var rarityOrder: Int {
    switch HeroCatalog.hero(id: definitionID)?.rarity {
    case .legendary: return 3
    case .epic: return 2
    case .rare: return 1
    default: return 0
    }
  }
}

/// Circular faction-gradient avatar with the hero's initial and a level badge.
struct HeroAvatar: View {
  let definition: HeroDefinition
  let level: Int
  var diameter: CGFloat = 48

  var body: some View {
    Circle()
      .fill(
        LinearGradient(
          colors: [DS.factionColor(definition.faction), DS.panelDark],
          startPoint: .topLeading, endPoint: .bottomTrailing))
      .frame(width: diameter, height: diameter)
      .overlay(
        Text(String(definition.name.prefix(1)))
          .font(.system(size: diameter * 0.4, weight: .heavy, design: .rounded))
          .foregroundColor(.white))
      .overlay(alignment: .bottom) {
        Text("Lv \(level)")
          .font(.system(size: diameter * 0.18, weight: .bold, design: .rounded))
          .foregroundColor(DS.emberDark)
          .padding(.horizontal, 4)
          .background(Capsule().fill(DS.goldLight))
          .offset(y: 4)
      }
  }
}
