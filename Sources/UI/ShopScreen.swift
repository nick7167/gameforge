import SwiftUI
import GameCore

/// All four revenue streams, driven by RevenueCat. Renders fine even when
/// purchases are unconfigured (buttons no-op with a gentle failure).
struct ShopScreen: View {
  @ObservedObject var purchases: PurchaseService
  let onDismiss: () -> Void

  var body: some View {
    NavigationStack {
      List {
        if !purchases.removeAdsOwned {
          Section("Remove Ads") {
            Button {
              Task { await purchases.purchase(productID: PurchaseService.removeAdsProductID) }
            } label: {
              HStack {
                VStack(alignment: .leading) {
                  Text("Remove Ads").bold()
                  Text("No revive ads + 1 free stabilize per run").font(.caption)
                }
                Spacer()
                Text("$3.99")
              }
            }
          }
        }
        Section("Coins") {
          ForEach(Economy.CoinPack.iapTiers, id: \.id) { tier in
            Button {
              Task { await purchases.purchase(productID: tier.id) }
            } label: {
              HStack {
                Text("\(tier.coins) Coins").bold()
                Spacer()
                Text("$\(String(format: "%.2f", tier.priceUSD))")
              }
            }
          }
        }
        Section {
          Button("Restore Purchases") {
            Task { await purchases.restore() }
          }
        }
      }
      .navigationTitle("Shop")
      .toolbar {
        Button("Done") { onDismiss() }
      }
    }
  }
}
