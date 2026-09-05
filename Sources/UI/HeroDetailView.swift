import GameCore
import SwiftUI

/// Full-screen hero detail: avatar header, lore, stat block with gear deltas,
/// level-up, and a 2×2 gear grid with an inventory equip sheet.
@MainActor
struct HeroDetailView: View {
  @ObservedObject var model: EmberGameModel
  let heroID: String

  @State private var pickerSlot: GearSlotSelection?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack(alignment: .topTrailing) {
      DS.emberDark.ignoresSafeArea()
      if let hero, let def = HeroCatalog.hero(id: hero.definitionID) {
        ScrollView {
          VStack(spacing: 16) {
            header(def, level: hero.level, stars: hero.stars)
            Text(def.lore)
              .font(.system(size: 13, design: .serif).italic())
              .foregroundColor(DS.textSecondary)
              .padding(.horizontal, 4)
            statPanel(hero)
            levelSection(hero)
            gearSection(hero)
          }
          .padding(.horizontal, 16)
          .padding(.top, 60)
          .padding(.bottom, 40)
        }
      } else {
        // Unknown hero: nothing to show besides the close button.
      }
      closeButton
    }
    .sheet(item: $pickerSlot) { selection in
      if let hero {
        GearPickerSheet(model: model, heroID: hero.definitionID, slot: selection.slot)
      }
    }
  }

  private var hero: OwnedHero? {
    model.profile.ownedHeroes.first { $0.definitionID == heroID }
  }

  private var closeButton: some View {
    Button {
      dismiss()
    } label: {
      Image(systemName: "xmark.circle.fill")
        .font(.system(size: 28))
        .foregroundColor(DS.textSecondary)
        .padding(.trailing, 16)
        .padding(.top, 52)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Header

  private func header(_ def: HeroDefinition, level: Int, stars: Int) -> some View {
    VStack(spacing: 6) {
      HeroAvatar(definition: def, level: level, diameter: 96)
      Text(def.name)
        .font(.system(size: 26, weight: .heavy, design: .rounded))
        .foregroundColor(DS.textPrimary)
      Text("\(def.rarity)".capitalized)
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundColor(DS.rarityColor(def.rarity))
      Text("\(def.faction) · \(def.role)")
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundColor(DS.textSecondary)
      Text(String(repeating: "★", count: max(1, stars)))
        .font(.system(size: 14))
        .foregroundColor(DS.goldLight)
    }
  }

  // MARK: - Stats (with gear delta vs. stripped copy)

  private func statPanel(_ hero: OwnedHero) -> some View {
    var noGear = hero
    noGear.gear = [:]
    let ungared = noGear.stats()
    let withGear = hero.stats()

    let rows: [StatRow] = [
      StatRow(label: "HP", before: ungared.hp, after: withGear.hp, kind: .hp),
      StatRow(label: "ATK", before: ungared.attack, after: withGear.attack, kind: .attack),
      StatRow(label: "DEF", before: ungared.defense, after: withGear.defense, kind: .defense),
      StatRow(label: "SPD", before: ungared.speed, after: withGear.speed, kind: .speed),
      StatRow(label: "CRIT", before: ungared.critChance, after: withGear.critChance, kind: .critChance),
      StatRow(label: "CRIT DMG", before: ungared.critDamage, after: withGear.critDamage, kind: .critDamage)
    ]

    return OrnatePanel {
      VStack(spacing: 10) {
        Text("Stats")
          .font(.system(size: 15, weight: .heavy, design: .rounded))
          .foregroundColor(DS.goldLight)
          .frame(maxWidth: .infinity, alignment: .leading)
        ForEach(rows) { row in
          statRow(label: row.label, before: row.before, after: row.after, kind: row.kind)
        }
      }
    }
  }

  private func statRow(label: String, before: Double, after: Double, kind: StatKind) -> some View {
    let delta = after - before
    return HStack {
      Text(label)
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundColor(DS.textSecondary)
      Spacer()
      Text(Self.formatted(after, kind: kind))
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundColor(DS.textPrimary)
      if delta > 0.001 {
        Text("+\(Self.formatted(delta, kind: kind))")
          .font(.system(size: 12, weight: .bold, design: .rounded))
          .foregroundColor(.green)
      }
    }
  }

  static func formatted(_ value: Double, kind: StatKind) -> String {
    switch kind {
    case .critChance, .critDamage:
      return "\(Int((value * 100).rounded()))%"
    case .hp, .attack, .defense, .speed:
      return Int(value.rounded()).formatted()
    }
  }

  // MARK: - Level up

  private var levelCap: Int { model.profile.accountLevel * 10 }

  private func levelSection(_ hero: OwnedHero) -> some View {
    let cost = EmberSession.heroLevelCost(level: hero.level)
    let atCap = hero.level >= levelCap
    let canAfford = model.profile.wallet.balance(of: .gold) >= cost
    return OrnatePanel {
      VStack(spacing: 10) {
        HStack {
          Text("Level")
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundColor(DS.goldLight)
          Spacer()
          Text("\(hero.level) / \(levelCap)")
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(DS.textPrimary)
        }
        GoldButton(
          title: atCap ? "Level Cap" : "Level Up — 🪙 \(cost)",
          style: atCap || !canAfford ? .disabled : .gold
        ) {
          model.levelUpHero(heroID: heroID)
        }
      }
    }
  }

  // MARK: - Gear

  private func gearSection(_ hero: OwnedHero) -> some View {
    VStack(spacing: 10) {
      Text("Gear")
        .font(.system(size: 15, weight: .heavy, design: .rounded))
        .foregroundColor(DS.goldLight)
        .frame(maxWidth: .infinity, alignment: .leading)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        ForEach(GearSlot.allCases, id: \.self) { slot in
          gearCard(hero, slot: slot)
        }
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(LinearGradient(colors: [DS.panelLight, DS.panelDark], startPoint: .top, endPoint: .bottom)))
  }

  @ViewBuilder
  private func gearCard(_ hero: OwnedHero, slot: GearSlot) -> some View {
    if let item = hero.gear[slot] {
      equippedGearCard(item, slot: slot)
    } else {
      emptyGearCard(slot)
    }
  }

  /// Equipped item card: rarity border, main stat, enhance level and an
  /// Enhance button (cost = EquipmentSystem.enhanceCost of current level).
  private func equippedGearCard(_ item: GearItem, slot: GearSlot) -> some View {
    let cost = EquipmentSystem.enhanceCost(level: item.enhanceLevel)
    let canAfford = model.profile.wallet.balance(of: .gold) >= cost
    return RarityFrame(rarity: item.rarity) {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("\(slot)".capitalized)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(DS.textSecondary)
          Spacer()
          Text("\(GearStatKindLabel.name(item.mainStat.kind)) \(Int(item.mainStat.value))")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(DS.textPrimary)
        }
        Text("+\(item.enhanceLevel)")
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundColor(DS.goldLight)
        GoldButton(
          title: "Enhance — 🪙 \(cost)",
          style: canAfford ? .gold : .disabled
        ) {
          model.enhanceGear(heroID: heroID, slot: slot)
        }
        .scaleEffect(0.55, anchor: .leading)
        .frame(height: 22)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
    .onTapGesture { pickerSlot = GearSlotSelection(slot: slot) }
  }

  private func emptyGearCard(_ slot: GearSlot) -> some View {
    Button {
      pickerSlot = GearSlotSelection(slot: slot)
    } label: {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(DS.textSecondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
        .background(RoundedRectangle(cornerRadius: 8).fill(DS.panelDark.opacity(0.6)))
        .frame(height: 66)
        .overlay(
          VStack(spacing: 2) {
            Text("\(slot)".capitalized)
              .font(.system(size: 11, weight: .bold, design: .rounded))
              .foregroundColor(DS.textSecondary)
            Text("Empty")
              .font(.system(size: 11, design: .rounded))
              .foregroundColor(DS.textSecondary.opacity(0.6))
          })
    }
    .buttonStyle(.plain)
  }
}

/// Wrapper making a gear slot presentable via sheet(item:) without a
/// retroactive conformance on the GameCore type.
struct GearSlotSelection: Identifiable {
  let slot: GearSlot
  var id: String { slot.rawValue }
}

/// One stat row in the detail stat panel.
struct StatRow: Identifiable {
  let label: String
  let before: Double
  let after: Double
  let kind: StatKind
  var id: String { label }
}

/// Human-readable stat labels (SPD/CRT/CRD) used by the gear cards.
enum GearStatKindLabel {
  static func name(_ kind: StatKind) -> String {
    switch kind {
    case .hp: return "HP"
    case .attack: return "ATK"
    case .defense: return "DEF"
    case .speed: return "SPD"
    case .critChance: return "CRT"
    case .critDamage: return "CRD"
    }
  }
}
