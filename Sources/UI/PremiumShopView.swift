import GameCore
import SwiftUI
import UIKit

/// Real-money shop (spec §12): Growth Bundle, gem packs, Monthly Card, Remove
/// Ads. Backed by RevenueCat; degrades gracefully when no API key is present.
struct PremiumShopView: View {
  @ObservedObject var model: EmberGameModel
  @ObservedObject var purchaseService: PurchaseService
  let onDismiss: () -> Void

  @State private var toast: String?

  var body: some View {
    ZStack {
      DS.emberDark.ignoresSafeArea()
      ScrollView {
        VStack(spacing: 14) {
          if !purchaseService.isConfigured {
            unavailableBanner
          }
          GrowthBundleCard(
            owned: purchaseService.growthBundleOwned, enabled: purchaseService.isConfigured
          ) {
            purchase(productID: PurchaseService.growthBundleProductID)
          }
          sectionTitle("💎 Gem Packs")
          VStack(spacing: 8) {
            ForEach(PurchaseService.gemPackProducts, id: \.id) { pack in
              GemPackRow(gems: pack.gems, price: pack.priceUSD, enabled: purchaseService.isConfigured) {
                purchase(productID: pack.id)
              }
            }
          }
          MonthlyCardCard(
            active: purchaseService.monthlyCardActive, enabled: purchaseService.isConfigured
          ) {
            purchase(productID: PurchaseService.monthlyCardProductID)
          }
          RemoveAdsCard(
            owned: purchaseService.removeAdsOwned, enabled: purchaseService.isConfigured
          ) {
            purchase(productID: PurchaseService.removeAdsProductID)
          }
          Button("Restore Purchases") {
            Task { await purchaseService.restore() }
          }
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(DS.textSecondary)
          .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 40)
      }
      dismissButton
      if let toast {
        toastCapsule(toast)
      }
    }
    .task { await purchaseService.refreshEntitlements() }
  }

  // MARK: - Buying

  private func purchase(productID: String) {
    guard purchaseService.isConfigured else {
      showToast("Store not configured")
      return
    }
    Task {
      let ok = await purchaseService.purchase(productID: productID)
      if ok {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showToast("Purchase complete!")
      } else {
        showToast("Purchase failed")
      }
    }
  }

  // MARK: - Pieces

  private var unavailableBanner: some View {
    Text("Purchases unavailable in this build")
      .font(.system(size: 12, weight: .bold, design: .rounded))
      .foregroundColor(DS.emberDark)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(Capsule().fill(DS.goldMid))
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 14, weight: .black, design: .rounded))
      .foregroundColor(DS.goldLight)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var dismissButton: some View {
    VStack {
      HStack {
        Spacer()
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(DS.textPrimary)
            .padding(10)
            .background(Circle().fill(Color.black.opacity(0.5)))
            .overlay(Circle().strokeBorder(DS.goldDeep.opacity(0.7), lineWidth: 1))
        }
        .padding(.trailing, 16)
        .padding(.top, 10)
      }
      Spacer()
    }
  }

  private func toastCapsule(_ message: String) -> some View {
    VStack {
      Spacer()
      Text(message)
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundColor(DS.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.8)))
        .overlay(Capsule().strokeBorder(DS.goldDeep.opacity(0.7), lineWidth: 1))
        .padding(.bottom, 60)
    }
    .allowsHitTesting(false)
  }

  private func showToast(_ message: String) {
    toast = message
    Task { @MainActor in
      try? Task.sleep(for: .seconds(2))
      toast = nil
    }
  }
}

/// "BEST VALUE" featured card with a gold gradient border.
private struct GrowthBundleCard: View {
  let owned: Bool
  let enabled: Bool
  let onBuy: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      OrnatePanel {
        VStack(spacing: 8) {
          Text("Growth Bundle")
            .font(.system(size: 20, weight: .black, design: .rounded))
            .foregroundColor(DS.goldLight)
          VStack(alignment: .leading, spacing: 4) {
            row("💎 550 gems")
            row("🦸 Rare hero of your choice")
            row("📦 Epic gear box")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 2)
          if owned {
            stateBadge("OWNED", color: Color(red: 0.45, green: 0.95, blue: 0.55))
          } else {
            GoldButton(title: "$4.99", style: enabled ? .gold : .disabled, action: onBuy)
          }
        }
        .frame(maxWidth: .infinity)
      }
      ribbon
    }
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(
          LinearGradient(colors: [DS.goldLight, DS.goldDeep, DS.goldLight], startPoint: .topLeading, endPoint: .bottomTrailing),
          lineWidth: 2.5))
    .shadow(color: DS.goldMid.opacity(0.35), radius: 8)
  }

  private var ribbon: some View {
    Text("BEST VALUE")
      .font(.system(size: 9, weight: .black, design: .rounded))
      .foregroundColor(DS.emberDark)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Capsule().fill(DS.goldLight))
      .padding(6)
  }

  private func row(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 13, weight: .semibold, design: .rounded))
      .foregroundColor(DS.textPrimary)
  }

  private func stateBadge(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.system(size: 13, weight: .black, design: .rounded))
      .foregroundColor(color)
  }
}

/// One gem pack row: gem art + count, price, buy.
private struct GemPackRow: View {
  let gems: Int
  let price: String
  let enabled: Bool
  let onBuy: () -> Void

  var body: some View {
    OrnatePanel {
      HStack(spacing: 12) {
        Text("💎").font(.system(size: 26))
        VStack(alignment: .leading, spacing: 2) {
          Text("\(gems.formatted()) Gems")
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundColor(DS.textPrimary)
          Text("Consumable currency pack")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(DS.textSecondary)
        }
        Spacer()
        GoldButton(title: price, style: enabled ? .gem : .disabled, action: onBuy)
      }
    }
  }
}

/// Monthly Card: subscription with daily gems and QoL boosts.
private struct MonthlyCardCard: View {
  let active: Bool
  let enabled: Bool
  let onBuy: () -> Void

  var body: some View {
    OrnatePanel {
      HStack(spacing: 12) {
        Text("🎴").font(.system(size: 26))
        VStack(alignment: .leading, spacing: 2) {
          Text("Monthly Card")
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundColor(DS.textPrimary)
          Text("Daily 300 gems · 4× speed · 24h idle cap")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(DS.textSecondary)
        }
        Spacer()
        if active {
          Text("ACTIVE")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundColor(Color(red: 0.45, green: 0.95, blue: 0.55))
        } else {
          GoldButton(title: "$4.99/mo", style: enabled ? .gem : .disabled, action: onBuy)
        }
      }
    }
  }
}

/// Remove Ads one-time purchase.
private struct RemoveAdsCard: View {
  let owned: Bool
  let enabled: Bool
  let onBuy: () -> Void

  var body: some View {
    OrnatePanel {
      HStack(spacing: 12) {
        Text("🚫").font(.system(size: 26))
        VStack(alignment: .leading, spacing: 2) {
          Text("Remove Ads")
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundColor(DS.textPrimary)
          Text("No more rewarded-ad prompts")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(DS.textSecondary)
        }
        Spacer()
        if owned {
          Text("OWNED")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundColor(Color(red: 0.45, green: 0.95, blue: 0.55))
        } else {
          GoldButton(title: "$3.99", style: enabled ? .gem : .disabled, action: onBuy)
        }
      }
    }
  }
}
