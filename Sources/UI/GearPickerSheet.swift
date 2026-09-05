import GameCore
import SwiftUI

/// Gear inventory picker: lists unequipped gear of one slot; "Equip" moves it
/// from the inventory to the hero (the previously equipped item returns to the
/// inventory — handled inside `EmberSession.equipGear`).
@MainActor
struct GearPickerSheet: View {
  @ObservedObject var model: EmberGameModel
  let heroID: String
  let slot: GearSlot

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    DS.emberDark.ignoresSafeArea()
      .overlay(
        VStack(spacing: 12) {
          Text("\(slot)".capitalized + " Gear")
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundColor(DS.goldLight)
            .padding(.top, 20)
          if available.isEmpty {
            Text("No gear of this type in your inventory.")
              .font(.system(size: 13, design: .rounded))
              .foregroundColor(DS.textSecondary)
              .padding(.top, 20)
          }
          ScrollView {
            VStack(spacing: 8) {
              ForEach(available) { item in
                row(item)
              }
            }
            .padding(.horizontal, 16)
          }
        }
      )
  }

  private var available: [GearItem] {
    model.profile.gearInventory.filter { $0.slot == slot }
  }

  private func row(_ item: GearItem) -> some View {
    HStack(spacing: 10) {
      Circle()
        .fill(DS.rarityColor(item.rarity))
        .frame(width: 10, height: 10)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(GearStatKindLabel.name(item.mainStat.kind)) \(Int(item.mainStat.value))")
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundColor(DS.textPrimary)
        Text("\(item.subStats.count) substats · +\(item.enhanceLevel)")
          .font(.system(size: 11, design: .rounded))
          .foregroundColor(DS.textSecondary)
      }
      Spacer()
      GoldButton(title: "Equip", style: .gold) {
        model.equipGear(heroID: heroID, item: item, slot: slot)
        dismiss()
      }
      .scaleEffect(0.7)
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 10).fill(DS.panelDark))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.rarityColor(item.rarity), lineWidth: 1))
  }
}
