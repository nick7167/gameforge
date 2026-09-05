import SwiftUI
import GameCore

/// Profile screen: avatar + editable name, squad showcase, lifetime stats.
struct ProfileView: View {
  @ObservedObject var model: EmberGameModel

  @State private var showRenameAlert = false
  @State private var nameInput = ""

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        Text("Profile")
          .font(.system(size: 28, weight: .heavy, design: .rounded))
          .foregroundColor(DS.goldLight)
          .frame(maxWidth: .infinity, alignment: .leading)
        identityPanel
        squadPanel
        statsPanel
        rankPanel
      }
      .padding(16)
    }
    .alert("Rename Hero", isPresented: $showRenameAlert) {
      TextField("Name", text: $nameInput)
      Button("Save") { model.renamePlayer(nameInput) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Choose the name rivals will fear (up to 20 characters).")
    }
  }

  // MARK: - Identity

  private var identityPanel: some View {
    HStack(spacing: 16) {
      avatar
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Text(model.profile.name)
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundColor(DS.textPrimary)
            .lineLimit(1)
          Button {
            nameInput = model.profile.name
            showRenameAlert = true
          } label: {
            Image(systemName: "pencil.circle.fill")
              .font(.system(size: 20))
              .foregroundColor(DS.goldLight)
          }
          .buttonStyle(.plain)
        }
        Text("Lv \(model.profile.accountLevel)")
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundColor(DS.textSecondary)
      }
      Spacer()
    }
  }

  private var avatar: some View {
    ZStack {
      Circle().fill(
        LinearGradient(colors: [DS.goldLight, DS.goldDeep], startPoint: .top, endPoint: .bottom))
      Text(String(model.profile.name.first.map(String.init) ?? "?"))
        .font(.system(size: 36, weight: .black, design: .rounded))
        .foregroundColor(DS.emberDark)
    }
    .frame(width: 74, height: 74)
    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 2))
    .shadow(color: DS.goldDeep.opacity(0.5), radius: 6)
  }

  // MARK: - Squad

  private var squadPanel: some View {
    OrnatePanel {
      VStack(alignment: .leading, spacing: 10) {
        Text("SQUAD")
          .font(.system(size: 12, weight: .black, design: .rounded))
          .foregroundColor(DS.textSecondary)
        HStack(spacing: 10) {
          ForEach(model.profile.squad, id: \.self) { id in
            squadCard(id)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func squadCard(_ id: String) -> some View {
    if let hero = model.profile.ownedHeroes.first(where: { $0.definitionID == id }),
      let def = HeroCatalog.hero(id: id) {
      VStack(spacing: 5) {
        RarityFrame(rarity: def.rarity) {
          Circle()
            .fill(
              LinearGradient(
                colors: [DS.factionColor(def.faction), DS.panelDark],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 46, height: 46)
            .overlay(
              Text(String(def.name.prefix(1)))
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundColor(.white))
        }
        Text(def.name)
          .font(.system(size: 10, weight: .bold, design: .rounded))
          .foregroundColor(DS.textPrimary)
          .lineLimit(1)
        Text("Lv \(hero.level)")
          .font(.system(size: 10, weight: .semibold, design: .rounded))
          .foregroundColor(DS.textSecondary)
      }
      .frame(maxWidth: .infinity)
    }
  }

  // MARK: - Stats

  private var statsPanel: some View {
    OrnatePanel {
      VStack(alignment: .leading, spacing: 10) {
        Text("RECORD")
          .font(.system(size: 12, weight: .black, design: .rounded))
          .foregroundColor(DS.textSecondary)
        statRow(label: "Total battles", value: model.profile.totalBattles.formatted())
        statRow(label: "Total summons", value: model.profile.totalSummons.formatted())
        statRow(label: "Best stage", value: model.profile.bestStage.display)
        statRow(
          label: "Wallet",
          value: "💎 \(model.profile.wallet.balance(of: .gems).formatted()) · 🪙 \(model.profile.wallet.balance(of: .gold).formatted())")
        statRow(label: "Squad power", value: model.squadPower().formatted())
      }
    }
  }

  private func statRow(label: String, value: String) -> some View {
    HStack {
      Text(label)
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundColor(DS.textSecondary)
      Spacer()
      Text(value)
        .font(.system(size: 14, weight: .heavy, design: .rounded))
        .foregroundColor(DS.textPrimary)
    }
  }

  // MARK: - Rank

  private var rankPanel: some View {
    OrnatePanel {
      HStack {
        Text("Season 1")
          .font(.system(size: 14, weight: .heavy, design: .rounded))
          .foregroundColor(DS.goldLight)
        Spacer()
        Text("Best stage \(model.profile.bestStage.display)")
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundColor(DS.textSecondary)
      }
    }
  }
}
