import AppKit
import HaloCore
import SwiftUI

/// Step 5: a summary of the setup, launch at login, and a way into the ring editor.
struct OnboardingDonePage: View {
    /// Finishes the guide and opens the global ring in Halo Settings.
    let customizeRing: () -> Void

    @ViewState private var celebrates = false
    /// Re-read whenever Halo becomes active: the user may have approved the login item in
    /// System Settings meanwhile.
    @ViewState private var loginItemStatus = LaunchAtLogin.status
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let settings = AppModel.shared.settings
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 54, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: celebrates)
                    .symbolEffectsRemoved(reduceMotion)
                    .accessibilityHidden(true)
                Text("You're All Set")
                    .font(.system(size: 28, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(settings.showMenuBarIcon
                     ? "Halo waits in the menu bar. Settings, pause and this guide are in its menu."
                     : "The menu bar icon is hidden: open Halo again from Applications to reach its settings.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
                    .fixedSize(horizontal: false, vertical: true)
            }

            summary(settings)
                .frame(maxWidth: 440)

            VStack(spacing: 10) {
                launchAtLogin(isOn: settings.launchAtLogin)
                Button("Customize Your Ring…", action: customizeRing)
                    .help("Close this guide and open the ring editor in Halo Settings")
            }
        }
        .frame(maxHeight: .infinity)
        .task {
            // Let the page settle in before the seal bounces.
            try? await Task.sleep(for: .milliseconds(350))
            celebrates = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemStatus = LaunchAtLogin.status
        }
    }

    // MARK: Summary

    private func summary(_ settings: AppSettings) -> some View {
        let accessibilityGranted = PermissionCenter.shared.status(.accessibility) == .granted
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                summaryLabel("Shortcut", symbol: "keyboard")
                if let trigger = settings.trigger {
                    OnboardingKeyCaps(combo: trigger)
                } else {
                    Text("None (menu bar only)").foregroundStyle(.secondary)
                }
            }
            GridRow {
                summaryLabel("Selection", symbol: "cursorarrow.click.2")
                Text(OnboardingFlow.name(of: settings.selectionMode))
            }
            GridRow {
                summaryLabel("Accessibility", symbol: "accessibility")
                if accessibilityGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Not yet: shortcut and window actions won't run")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onboardingCard()
    }

    private func summaryLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(.secondary)
    }

    // MARK: Launch at login

    @ViewBuilder
    private func launchAtLogin(isOn: Bool) -> some View {
        let unavailableReason: String? = if case .unavailable(let reason) = loginItemStatus { reason } else { nil }
        Toggle("Launch Halo at login", isOn: Binding(
            get: { AppModel.shared.settings.launchAtLogin },
            set: { newValue in
                // The app delegate registers the login item when the setting changes.
                AppModel.shared.updateSettings(newValue ? "Turn On Launch at Login" : "Turn Off Launch at Login") {
                    $0.launchAtLogin = newValue
                }
                loginItemStatus = LaunchAtLogin.status
            }
        ))
        .toggleStyle(.switch)
        // Can always be turned off; turning on needs a login item macOS can find.
        .disabled(unavailableReason != nil && !isOn)

        if loginItemStatus == .requiresApproval {
            HStack(spacing: 8) {
                Label("Allow Halo in System Settings › General › Login Items.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Open Login Items…") { LaunchAtLogin.openLoginItemsSettings() }
            }
            .font(.callout)
        } else if let unavailableReason {
            Text(unavailableReason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }
}
