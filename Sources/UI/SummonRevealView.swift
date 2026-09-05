import GameCore
import SwiftUI

/// Full-screen summon reveal ritual (spec §6.2): portal glow, then result
/// cards appearing one by one. Legendary cards pulse gold.
@MainActor
struct SummonRevealView: View {
  let items: [GachaEngine.PullResult]
  var onDismiss: () -> Void

  @State private var portalVisible = false
  @State private var revealedCount = 0
  @State private var revealTask: Task<Void, Never>?

  private var allRevealed: Bool { revealedCount >= items.count }

  var body: some View {
    ZStack {
      Color.black.opacity(0.92).ignoresSafeArea()
      if portalVisible {
        portalGlow
        cards
        if allRevealed {
          tapToContinue
        }
      }
    }
    .onAppear { runRevealSequence() }
    .onDisappear { revealTask?.cancel() }
    .contentShape(Rectangle())
    .onTapGesture { dismissIfReady() }
  }

  // MARK: - Phases

  /// Phase 1: portal glow. Phase 2: cards staggered in. Driven by a single
  /// task chain with Task.sleep — no timers, no dispatch queues.
  private func runRevealSequence() {
    revealTask?.cancel()
    revealTask = Task { @MainActor in
      withAnimation(.easeOut(duration: 0.6)) { portalVisible = true }
      try? await Task.sleep(for: .milliseconds(600))
      guard !Task.isCancelled else { return }
      for index in items.indices {
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { revealedCount = index + 1 }
        try? await Task.sleep(for: .milliseconds(350))
      }
    }
  }

  private func dismissIfReady() {
    guard allRevealed else { return }
    revealTask?.cancel()
    onDismiss()
  }

  // MARK: - Portal glow

  private var portalGlow: some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [DS.goldLight.opacity(0.9), DS.goldMid.opacity(0.35), Color.clear],
          center: .center, startRadius: 10, endRadius: 200))
      .frame(width: 380, height: 380)
      .blur(radius: 12)
      .scaleEffect(portalVisible ? 1 : 0.2)
  }

  // MARK: - Cards

  private var cards: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 14) {
        ForEach(items.indices, id: \.self) { index in
          if index < revealedCount {
            RevealCard(result: items[index])
              .transition(.scale.combined(with: .opacity))
          } else {
            Color.clear.frame(width: 140, height: 190)
          }
        }
      }
      .padding(16)
    }
    .scrollDisabled(!allRevealed)
  }

  private var tapToContinue: some View {
    Text("TAP TO CONTINUE")
      .font(.system(size: 13, weight: .heavy, design: .rounded))
      .foregroundColor(DS.goldLight)
      .padding(.top, 8)
      .frame(maxHeight: .infinity, alignment: .bottom)
      .padding(.bottom, 24)
  }
}

// MARK: - One result card

/// A single revealed hero: rarity-framed, NEW badge or dupe-shard caption.
private struct RevealCard: View {
  let result: GachaEngine.PullResult
  @State private var pulse = false

  private var hero: HeroDefinition { result.hero }

  var body: some View {
    RarityFrame(rarity: hero.rarity) {
      VStack(spacing: 6) {
        ZStack(alignment: .topTrailing) {
          RoundedRectangle(cornerRadius: 8)
            .fill(
              LinearGradient(
                colors: [DS.factionColor(hero.faction).opacity(0.8), DS.panelDark],
                startPoint: .top, endPoint: .bottom))
            .overlay(
              Text(String(hero.name.first ?? "?"))
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.92)))
            .frame(width: 108, height: 92)
          if result.isNew {
            Text("NEW")
              .font(.system(size: 10, weight: .black, design: .rounded))
              .foregroundColor(DS.emberDark)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Capsule().fill(DS.goldLight))
              .offset(x: 6, y: -8)
          }
        }
        Text(hero.name)
          .font(.system(size: 14, weight: .heavy, design: .rounded))
          .foregroundColor(DS.textPrimary)
          .lineLimit(1)
        Text(hero.rarity.rawValue == 3 ? "Legendary" : hero.rarity.rawValue == 2 ? "Epic" : hero.rarity.rawValue == 1 ? "Rare" : "Common")
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundColor(DS.rarityColor(hero.rarity))
        Text(starRow)
          .font(.system(size: 10))
          .foregroundColor(DS.goldLight)
        if !result.isNew {
          Text("DUPE +\(result.factionShardsAwarded) shards")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(DS.factionColor(hero.faction))
        }
      }
      .padding(8)
    }
    .frame(width: 140, height: 190)
    .modifier(LegendaryGlow(isLegendary: hero.rarity == .legendary, pulse: pulse))
    .onAppear {
      guard hero.rarity == .legendary else { return }
      withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
        pulse = true
      }
    }
  }

  private var starRow: String {
    let stars = max(1, hero.rarity.rawValue + 1)
    return String(repeating: "★", count: stars)
  }
}

/// Gold pulsing glow applied to legendary reveal cards.
private struct LegendaryGlow: ViewModifier {
  let isLegendary: Bool
  let pulse: Bool

  func body(content: Content) -> some View {
    content.shadow(
      color: isLegendary ? DS.goldMid.opacity(pulse ? 0.95 : 0.35) : .black.opacity(0.5),
      radius: pulse ? 18 : 8)
  }
}
