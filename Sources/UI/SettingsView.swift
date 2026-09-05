import SwiftUI

/// Settings screen: audio/notification prefs (persisted for the upcoming
/// audio + notifications tasks), account actions, data reset, about.
struct SettingsView: View {
  @ObservedObject var model: EmberGameModel
  @ObservedObject var purchaseService: PurchaseService

  @Environment(\.dismiss) private var dismiss

  @AppStorage("musicEnabled") private var musicEnabled = true
  @AppStorage("sfxEnabled") private var sfxEnabled = true
  @AppStorage("notifIdle") private var notifIdle = true
  @AppStorage("notifDaily") private var notifDaily = true

  @State private var showDeleteConfirmation = false
  @State private var restoring = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text("Settings")
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .foregroundColor(DS.goldLight)
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 26))
              .foregroundColor(DS.textSecondary)
          }
          .buttonStyle(.plain)
        }
        audioSection
        notificationsSection
        accountSection
        dataSection
        aboutSection
      }
      .padding(16)
    }
    .confirmationDialog(
      "Delete account?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
      Button("Delete All Data", role: .destructive) {
        model.resetAll()
        dismiss()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This permanently erases your profile, heroes and progress. It cannot be undone.")
    }
  }

  // MARK: - Sections

  private var audioSection: some View {
    OrnatePanel {
      VStack(alignment: .leading, spacing: 12) {
        sectionLabel("AUDIO")
        Toggle("Music", isOn: $musicEnabled)
        Toggle("Sound effects", isOn: $sfxEnabled)
      }
    }
    .tint(DS.goldMid)
  }

  private var notificationsSection: some View {
    OrnatePanel {
      VStack(alignment: .leading, spacing: 12) {
        sectionLabel("NOTIFICATIONS")
        Toggle("Idle chest ready", isOn: $notifIdle)
        Toggle("Daily reset reminder", isOn: $notifDaily)
      }
    }
    .tint(DS.goldMid)
  }

  private var accountSection: some View {
    OrnatePanel {
      VStack(alignment: .leading, spacing: 12) {
        sectionLabel("ACCOUNT")
        Button {
          Task { await GameCenterService().authenticate() }
        } label: {
          HStack {
            Image(systemName: "gamecontroller.fill")
            Text("Sign in with Game Center")
          }
          .font(.system(size: 14, weight: .heavy, design: .rounded))
          .foregroundColor(DS.textPrimary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(RoundedRectangle(cornerRadius: 10).fill(DS.panelLight))
          .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.goldDeep.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        Button {
          restoring = true
          Task {
            await purchaseService.refreshEntitlements()
            restoring = false
          }
        } label: {
          HStack {
            if restoring {
              ProgressView().tint(DS.textPrimary)
            }
            Text("Restore Purchases")
          }
          .font(.system(size: 14, weight: .heavy, design: .rounded))
          .foregroundColor(DS.textPrimary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(RoundedRectangle(cornerRadius: 10).fill(DS.panelLight))
          .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.goldDeep.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var dataSection: some View {
    OrnatePanel {
      VStack(alignment: .leading, spacing: 12) {
        sectionLabel("DATA")
        Button {
          showDeleteConfirmation = true
        } label: {
          Text("Delete Account")
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.36))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.red.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var aboutSection: some View {
    OrnatePanel {
      VStack(alignment: .leading, spacing: 6) {
        sectionLabel("ABOUT")
        Text("Emberfall Realms v0.1.0")
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundColor(DS.textPrimary)
        Text(appVersionLine)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundColor(DS.textSecondary)
        Text("Forged with fire in the Emberfall forges. © 2026")
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundColor(DS.textSecondary)
      }
    }
  }

  private var appVersionLine: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    return "Build \(build) · version \(version)"
  }

  private func sectionLabel(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .black, design: .rounded))
      .foregroundColor(DS.textSecondary)
  }
}
