import SwiftUI
import GameCore

/// Emberfall Realms design system (spec §13): dark + glow, gold ornate UI.
enum DS {
  // Palette (from the approved WebGL prototype)
  static let emberDark = Color(red: 0.07, green: 0.04, blue: 0.12)
  static let panelDark = Color(red: 0.13, green: 0.09, blue: 0.20)
  static let panelLight = Color(red: 0.22, green: 0.16, blue: 0.33)
  static let goldLight = Color(red: 1.00, green: 0.84, blue: 0.44)
  static let goldMid = Color(red: 0.94, green: 0.71, blue: 0.16)
  static let goldDeep = Color(red: 0.77, green: 0.50, blue: 0.05)
  static let textPrimary = Color(red: 1.00, green: 0.91, blue: 0.66)
  static let textSecondary = Color(red: 0.72, green: 0.66, blue: 0.55)

  static func rarityColor(_ rarity: Rarity) -> Color {
    Color(hex: rarity.uiColorHex)
  }

  static func factionColor(_ faction: Faction) -> Color {
    switch faction {
    case .ember: return Color(red: 1.00, green: 0.48, blue: 0.16)
    case .frost: return Color(red: 0.31, green: 0.76, blue: 0.97)
    case .verdant: return Color(red: 0.49, green: 0.85, blue: 0.35)
    case .void: return Color(red: 0.61, green: 0.43, blue: 1.00)
    }
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}

/// Chunky beveled gold button (prototype-verified styling).
struct GoldButton: View {
  enum Style { case gold, gem, disabled }
  let title: String
  let style: Style
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 16, weight: .heavy, design: .rounded))
        .foregroundColor(style == .gem ? .white : DS.emberDark)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(
          Capsule().fill(
            LinearGradient(
              colors: style == .gem
                ? [Color(red: 0.72, green: 0.55, blue: 1.0), Color(red: 0.36, green: 0.13, blue: 0.71)]
                : [DS.goldLight, DS.goldMid, DS.goldDeep],
              startPoint: .top, endPoint: .bottom))
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
        .opacity(style == .disabled ? 0.45 : 1)
    }
    .disabled(style == .disabled)
  }
}

/// Gold-bordered dark panel.
struct OrnatePanel<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(14)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(LinearGradient(colors: [DS.panelLight, DS.panelDark], startPoint: .top, endPoint: .bottom)))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(
            LinearGradient(colors: [DS.goldLight, DS.goldDeep, DS.goldLight], startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1.5))
      .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
  }
}

/// Currency chip for the top bar. Optionally shows a small "\+" affordance
/// (used on the gems chip to open the premium shop).
struct CurrencyChip: View {
  let icon: String
  let value: Int
  var showsPlus = false
  var action: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 5) {
      Text(icon).font(.system(size: 13))
      Text(value.formatted())
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundColor(DS.textPrimary)
      if showsPlus {
        Text("+")
          .font(.system(size: 12, weight: .black, design: .rounded))
          .foregroundColor(DS.goldLight)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Capsule().fill(Color.black.opacity(0.45)))
    .overlay(Capsule().strokeBorder(DS.goldDeep.opacity(0.7), lineWidth: 1))
    .contentShape(Capsule())
    .onTapGesture { action?() }
  }
}

/// Rarity-colored frame for hero/gear cards.
struct RarityFrame<Content: View>: View {
  let rarity: Rarity
  let content: Content

  init(rarity: Rarity, @ViewBuilder content: () -> Content) {
    self.rarity = rarity
    self.content = content()
  }

  var body: some View {
    content
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.rarityColor(rarity), lineWidth: 2))
      .shadow(color: DS.rarityColor(rarity).opacity(0.5), radius: 4)
  }
}

/// Damage-number text styling (spec §13: big outlined numbers with glow).
/// Kind mirrors BattleScene.DamageKind (Task 3) without coupling to SceneKit.
enum DamageNumberStyle {
  enum Kind { case normal, crit, ult, heal }

  static func font(for kind: Kind) -> Font {
    switch kind {
    case .normal: return .system(size: 22, weight: .heavy, design: .rounded)
    case .crit: return .system(size: 30, weight: .heavy, design: .rounded)
    case .ult: return .system(size: 26, weight: .black, design: .rounded)
    case .heal: return .system(size: 20, weight: .bold, design: .rounded)
    }
  }

  static func color(for kind: Kind) -> Color {
    switch kind {
    case .normal: return .white
    case .crit: return DS.goldLight
    case .ult: return Color(red: 1.00, green: 0.42, blue: 0.28)
    case .heal: return Color(red: 0.45, green: 0.95, blue: 0.55)
    }
  }

  static func glowColor(for kind: Kind) -> Color {
    switch kind {
    case .crit, .ult: return DS.goldMid
    case .heal: return Color(red: 0.30, green: 0.80, blue: 0.40)
    case .normal: return .black
    }
  }

  /// Outlined, glowing damage number: layered shadows approximate the
  /// prototype's thick black outline + colored glow.
  static func outlinedText(_ string: String, kind: Kind) -> some View {
    Text(string)
      .font(font(for: kind))
      .foregroundColor(color(for: kind))
      .shadow(color: .black.opacity(0.9), radius: 1)
      .shadow(color: .black.opacity(0.9), radius: 1)
      .shadow(color: glowColor(for: kind).opacity(0.8), radius: 4)
  }
}
