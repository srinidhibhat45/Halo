import AppKit
import HaloCore
import SwiftUI

/// Icon, version and credits, a link to the configuration, and a cheat sheet of the ring's
/// keyboard and mouse controls.
struct AboutPane: View {
    private var model: AppModel { .shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                identity
                HStack(spacing: 10) {
                    Button("Show Config Folder") { ConfigFileAccess.revealInFinder() }
                    Button("Show Welcome Guide") { SettingsRouter.shared.openOnboarding() }
                }
                UpdatesSection()
                RingCheatSheet(trigger: model.settings.trigger)
            }
            .padding(32)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
    }

    private var identity: some View {
        VStack(spacing: 8) {
            appIcon
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)
            Text("Halo")
                .font(.largeTitle.bold())
            Text(Self.versionText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .textSelection(.enabled)
            Text("Your actions in a ring around the pointer, one shortcut away.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Text("Inspired by Logitech's Actions Ring; not affiliated with Logitech.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: HaloSymbol.ring)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.tint)
        }
    }

    /// "Version 1.0.0 (42)", or "Development build" when run outside the app bundle.
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        func value(_ key: String) -> String? {
            guard let text = info?[key] as? String, !text.isEmpty, !text.hasPrefix("__") else { return nil }
            return text
        }
        guard let version = value("CFBundleShortVersionString") else { return "Development build" }
        if let build = value("CFBundleVersion"), build != version { return "Version \(version) (\(build))" }
        return "Version \(version)"
    }
}

/// A compact reference of the ring's controls.
private struct RingCheatSheet: View {
    let trigger: KeyCombo?

    private struct Entry: Identifiable {
        let keys: [String]
        let spokenKeys: String
        let meaning: String
        var id: String { meaning }
    }

    var body: some View {
        GroupBox {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 9) {
                ForEach(entries) { entry in
                    GridRow {
                        HStack(spacing: 4) {
                            ForEach(Array(entry.keys.enumerated()), id: \.offset) { _, key in
                                KeyCap(key)
                            }
                        }
                        .gridColumnAlignment(.trailing)
                        Text(entry.meaning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.spokenKeys): \(entry.meaning)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            Label("Using the Ring", systemImage: "keyboard")
                .font(.headline)
        }
    }

    private var entries: [Entry] {
        let key = trigger?.displayString ?? "Trigger"
        let spoken = trigger?.accessibilityLabel ?? "the trigger"
        return [
            Entry(keys: [key, "Tap"], spokenKeys: "Tap \(spoken)", meaning: "Open the ring, then click an action"),
            Entry(keys: [key, "Hold"], spokenKeys: "Hold \(spoken)", meaning: "Point at an action and let go to run it"),
            Entry(keys: ["1", "–", "9", "0"], spokenKeys: "1 to 9, and 0", meaning: "Run the action in that slot"),
            Entry(keys: ["←", "↑", "→", "↓"], spokenKeys: "Arrow keys", meaning: "Move the highlight"),
            Entry(keys: ["⇥", "⇧⇥"], spokenKeys: "Tab, Shift Tab", meaning: "Next or previous slot"),
            Entry(keys: ["↩", "Space"], spokenKeys: "Return or Space", meaning: "Run the highlighted action"),
            Entry(keys: ["⎋"], spokenKeys: "Escape", meaning: "Leave a nested ring, or close"),
            Entry(keys: ["⌫"], spokenKeys: "Delete", meaning: "Leave a nested ring"),
            Entry(keys: ["⌘", "Click"], spokenKeys: "Command click", meaning: "Edit that slot in Halo Settings"),
            Entry(keys: ["Scroll"], spokenKeys: "Scroll", meaning: "Change volume or brightness while its slot is highlighted"),
            Entry(keys: ["Click outside"], spokenKeys: "Click outside the ring", meaning: "Close without running anything"),
        ]
    }
}

/// Update status, a manual check and the automatic-check switch.
private struct UpdatesSection: View {
    private var updates: UpdateController { .shared }
    private var model: AppModel { .shared }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                status
                Spacer(minLength: 12)
                if let version = updates.availableVersion {
                    Button("Install \(version.description)") { Task { await updates.installAvailableUpdate() } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Check for Updates") { Task { await updates.check(userInitiated: true) } }
                        .disabled(updates.isBusy)
                }
            }
            Toggle("Check for updates automatically", isOn: Binding(
                get: { model.settings.checksForUpdates },
                set: { on in model.updateSettings(on ? "Turn On Update Checks" : "Turn Off Update Checks") { $0.checksForUpdates = on } }
            ))
            .frame(maxWidth: .infinity, alignment: .leading)
            if let page = UpdateController.releasesPage {
                Link("Release notes and downloads", destination: page)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var status: some View {
        switch updates.state {
        case .checking:
            Label("Checking…", systemImage: "arrow.triangle.2.circlepath")
        case .available(let version):
            Label("Halo \(version.description) is available", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
        case .downloading(let version):
            Label("Downloading \(version.description)…", systemImage: "arrow.down.circle")
        case .installing(let version):
            Label("Installing \(version.description)…", systemImage: "gearshape.arrow.triangle.2.circlepath")
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .lineLimit(2)
        case .idle, .upToDate:
            if let date = updates.lastChecked {
                Label("Up to date · checked \(date.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label("Updates come from GitHub Releases", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
