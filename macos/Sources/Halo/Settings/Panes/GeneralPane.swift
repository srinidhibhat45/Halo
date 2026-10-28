import AppKit
import HaloCore
import SwiftUI

/// General settings: the trigger, how the ring picks an action, app behaviour, and the
/// configuration file.
struct GeneralPane: View {
    var body: some View {
        Form {
            TriggerSection()
            SelectionSection()
            BehaviorSection()
            ConfigurationSection()
        }
        .formStyle(.grouped)
    }
}

// MARK: - Trigger

private struct TriggerSection: View {
    @ViewState private var showsMouseHelp = false

    private var model: AppModel { .shared }

    var body: some View {
        Section {
            LabeledContent {
                ShortcutRecorder(combo: .appSetting(\.trigger, "Change Trigger"), purpose: .trigger)
            } label: {
                Text("Shortcut")
                Text("Opens the ring at the pointer, from any app.")
            }
            TriggerStatusRow()
            if model.settings.trigger != KeyCombo.defaultTrigger {
                LabeledContent {
                    Button("Use \(KeyCombo.defaultTrigger.displayString)") {
                        model.updateSettings("Use Default Trigger") { $0.trigger = KeyCombo.defaultTrigger }
                    }
                    .accessibilityLabel("Use the default shortcut, \(KeyCombo.defaultTrigger.accessibilityLabel)")
                } label: {
                    Text("Default shortcut")
                    Text("\(KeyCombo.defaultTrigger.accessibilityLabel): unused by macOS and easy to give a mouse button.")
                }
            }
            DisclosureGroup("How to use a mouse button", isExpanded: $showsMouseHelp) {
                MouseButtonHelp(trigger: model.settings.trigger ?? KeyCombo.defaultTrigger)
            }
            TriggerCalibrationView()
        } header: {
            Text("Trigger")
        }
    }
}

/// Whether the trigger is registered, with the reason when it isn't.
private struct TriggerStatusRow: View {
    private var model: AppModel { .shared }

    var body: some View {
        LabeledContent {
            badge
        } label: {
            Text("Status")
            if let detail { Text(detail) }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if model.isPaused {
            HStack(spacing: 8) {
                StatusBadge("Paused", symbol: "pause.circle.fill", tone: .caution)
                Button("Resume") { model.isPaused = false }
            }
        } else if let trigger = model.settings.trigger {
            if HotKeyCenter.shared.registeredTrigger == trigger {
                StatusBadge("Ready", symbol: "checkmark.circle.fill", tone: .positive)
            } else {
                StatusBadge("Not Active", symbol: "exclamationmark.triangle.fill", tone: .caution)
            }
        } else {
            StatusBadge("No Shortcut", symbol: "minus.circle.fill", tone: .neutral)
        }
    }

    private var detail: String? {
        if model.isPaused { return "Halo ignores the trigger until you resume it." }
        guard let trigger = model.settings.trigger else {
            return "Record a shortcut, or open the ring from the menu bar."
        }
        let hotKeys = HotKeyCenter.shared
        if hotKeys.registeredTrigger == trigger { return nil }
        return hotKeys.lastRegistrationError
            ?? "macOS didn't accept \(trigger.displayString). Another app may be using it; try a different shortcut."
    }
}

/// How to point a mouse button at the trigger in common mouse utilities.
private struct MouseButtonHelp: View {
    let trigger: KeyCombo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Halo opens on a keyboard shortcut, so any mouse whose software can send one can open the ring. Give a button the shortcut \(trigger.displayString):")
                .fixedSize(horizontal: false, vertical: true)
            step(symbol: "computermouse",
                 "**Logi Options+:** select your mouse, open Buttons, pick a button, choose Keyboard shortcut and press \(trigger.displayString).")
            step(symbol: "cursorarrow.click.2",
                 "**BetterTouchTool:** under Normal Mice, add the button as a trigger, assign a keyboard shortcut action and record \(trigger.displayString).")
            step(symbol: "slider.horizontal.3",
                 "**SteerMouse, Mac Mouse Fix and others:** set the button's action to a keystroke or keyboard shortcut and record \(trigger.displayString).")
            Text("Then use Test Your Trigger to see whether holding the button works with your mouse software.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(.vertical, 4)
    }

    private func step(symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Test Your Trigger": measures how long the trigger stays down while the user holds their
/// mouse button, to tell whether their mouse software holds the shortcut or only taps it, and
/// offers the selection mode that suits it.
private struct TriggerCalibrationView: View {
    private enum Phase: Equatable {
        case idle
        case listening
        case measured(TimeInterval)
    }

    /// Releases shorter than this mean the software sends a tap, however long the button is held.
    private static let tapLimit: TimeInterval = 0.25
    /// Holds at least this long mean the software holds the shortcut while the button is down.
    private static let holdMinimum: TimeInterval = 0.5

    @ViewState private var phase: Phase = .idle

    private var model: AppModel { .shared }
    private var trigger: KeyCombo? { model.settings.trigger }

    /// The test needs a registered trigger that isn't paused.
    private var canTest: Bool {
        guard let trigger, !model.isPaused else { return false }
        return HotKeyCenter.shared.registeredTrigger == trigger
    }

    var body: some View {
        Group {
            switch phase {
            case .idle:
                LabeledContent {
                    Button("Test Your Trigger…", action: start)
                        .disabled(!canTest)
                } label: {
                    Text("Test your trigger")
                    Text("Checks whether your mouse software holds the shortcut down, so hold-and-release can work.")
                }
            case .listening:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Press and hold your mouse button (or \(trigger?.displayString ?? "the shortcut")) for about a second, then let go.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Cancel", action: stop)
                }
                .accessibilityElement(children: .contain)
                // Only this row: leaving the pane mid-test must give the trigger back.
                .onDisappear(perform: stop)
            case .measured(let duration):
                result(for: duration)
            }
        }
    }

    @ViewBuilder
    private func result(for duration: TimeInterval) -> some View {
        let held = "\(duration.formatted(.number.precision(.fractionLength(2)))) s"
        let mode = model.settings.selectionMode
        VStack(alignment: .leading, spacing: 10) {
            if duration >= Self.holdMinimum {
                Label {
                    Text("**Holding works.** The shortcut stayed down for \(held). Hold the button, point at an action and let go.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if mode == .tapThenClick {
                    Text("Tap, Then Click ignores releases. Switch to Automatic to also choose by letting go.")
                        .foregroundStyle(.secondary)
                }
            } else if duration < Self.tapLimit {
                Label {
                    Text("**Your mouse software sends a quick tap** (\(held)), even while you hold the button. Tap to open the ring, then click an action.")
                } icon: {
                    Image(systemName: "hand.tap.fill").foregroundStyle(.orange)
                }
                switch mode {
                case .holdAndRelease:
                    Text("Hold and Release can't work with a tap: the ring would close straight away.")
                        .foregroundStyle(.secondary)
                case .auto:
                    Text("Automatic already handles taps: the ring stays open until you click.")
                        .foregroundStyle(.secondary)
                case .tapThenClick:
                    EmptyView()
                }
            } else {
                Label {
                    Text("**Released after \(held).** That's too short to tell. Hold the button a little longer and try again.")
                } icon: {
                    Image(systemName: "questionmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            HStack {
                if let suggestion = suggestedMode(for: duration, current: mode) {
                    let title = "Use \(SelectionSection.title(for: suggestion))"
                    // Prominent only when the current mode doesn't work with this mouse software.
                    if mode == .auto {
                        Button(title) { choose(suggestion) }
                    } else {
                        Button(title) { choose(suggestion) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Button("Test Again", action: start)
                Button("Done") { phase = .idle }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }

    /// The mode to offer after a measurement, or nil when the current one already suits.
    private func suggestedMode(for duration: TimeInterval, current: SelectionMode) -> SelectionMode? {
        if duration >= Self.holdMinimum { return current == .tapThenClick ? .auto : nil }
        if duration < Self.tapLimit { return current == .tapThenClick ? nil : .tapThenClick }
        return nil
    }

    private func choose(_ mode: SelectionMode) {
        model.updateSettings("Change Selection Mode") { $0.selectionMode = mode }
        phase = .idle
    }

    private func start() {
        phase = .listening
        OverlayController.shared.calibration = { duration in
            OverlayController.shared.calibration = nil
            phase = .measured(duration)
        }
    }

    private func stop() {
        guard phase == .listening else { return }
        OverlayController.shared.calibration = nil
        phase = .idle
    }
}

// MARK: - Selection

private struct SelectionSection: View {
    @ViewState private var holdDraft: Double?

    private var model: AppModel { .shared }

    var body: some View {
        let settings = model.settings
        let hold = DeferredSliderValue(saved: settings.holdThreshold, draft: $holdDraft) { value in
            AppModel.shared.updateSettings("Change Hold Threshold") { $0.holdThreshold = value }
        }
        let milliseconds = Int((hold.value.wrappedValue * 1000).rounded())
        let isAuto = settings.selectionMode == .auto

        Section {
            Picker("Mode", selection: .appSetting(\.selectionMode, "Change Selection Mode")) {
                ForEach(SelectionMode.allCases, id: \.self) { mode in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title(for: mode))
                        Text(Self.explanation(for: mode))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(mode)
                    .accessibilityElement(children: .combine)
                }
            }
            .pickerStyle(.radioGroup)

            LabeledContent {
                Slider(value: hold.value, in: AppSettings.holdThresholdRange, step: 0.01) {
                    Text("Hold threshold")
                } minimumValueLabel: {
                    Text("Short")
                } maximumValueLabel: {
                    Text("Long")
                } onEditingChanged: { hold.editingChanged($0) }
                .labelsHidden()
                .accessibilityValue("\(milliseconds) milliseconds")
            } label: {
                Text("Hold threshold: \(milliseconds) ms")
                    .monospacedDigit()
                Text(isAuto
                     ? "Let go sooner and the ring stays open; later and the highlighted action runs."
                     : "Used only in Automatic mode.")
            }
            .disabled(!isAuto)

            Picker("Placement", selection: .appSetting(\.placement, "Change Placement")) {
                Text("At the pointer").tag(RingPlacement.cursor)
                Text("Center of the screen").tag(RingPlacement.screenCenter)
            }
        } header: {
            Text("Selection")
        }
    }

    static func title(for mode: SelectionMode) -> String {
        switch mode {
        case .auto: "Automatic"
        case .tapThenClick: "Tap, Then Click"
        case .holdAndRelease: "Hold and Release"
        }
    }

    static func explanation(for mode: SelectionMode) -> String {
        switch mode {
        case .auto: "Tap to keep the ring open and click, or hold, point and let go."
        case .tapThenClick: "The ring stays open; click an action or press its number."
        case .holdAndRelease: "Hold, point at an action and let go. Letting go in the middle cancels."
        }
    }
}

// MARK: - Behavior

private struct BehaviorSection: View {
    private var model: AppModel { .shared }

    var body: some View {
        Section {
            Toggle(isOn: .appSetting(\.appRingsEnabled, "Change App Rings")) {
                Text("Use app rings")
                Text("When an app with its own ring is in front, show that ring instead of Everywhere.")
            }
            LaunchAtLoginRows()
            Toggle(isOn: .appSetting(\.showMenuBarIcon, "Change Menu Bar Icon")) {
                Text("Show menu bar icon")
                Text(model.settings.showMenuBarIcon
                     ? "If you hide it, open Halo again from Applications or Spotlight to get back to these settings."
                     : "Hidden. To get back to these settings, open Halo again from Applications or Spotlight.")
            }
            Toggle(isOn: .appSetting(\.showConfirmations, "Change Confirmations")) {
                Text("Show confirmations")
                Text("A brief badge after actions with no visible result, such as Copy or Mute.")
            }
        } header: {
            Text("Behavior")
        }
    }
}

/// The launch-at-login switch plus, when macOS wants it, a prompt to approve the login item.
private struct LaunchAtLoginRows: View {
    @ViewState private var status = LaunchAtLogin.status

    private var model: AppModel { .shared }

    var body: some View {
        let unavailableReason: String? = if case .unavailable(let reason) = status { reason } else { nil }
        Group {
            Toggle(isOn: Binding {
                AppModel.shared.settings.launchAtLogin
            } set: { isOn in
                // The app delegate registers the login item when the setting changes.
                AppModel.shared.updateSettings(isOn ? "Turn On Launch at Login" : "Turn Off Launch at Login") { $0.launchAtLogin = isOn }
                status = LaunchAtLogin.status
            }) {
                Text("Launch at login")
                Text(unavailableReason ?? "Start Halo in the background when you log in.")
            }
            // Can always be turned off; turning on needs a login item macOS can find.
            .disabled(unavailableReason != nil && !model.settings.launchAtLogin)
            if status == .requiresApproval {
                LabeledContent {
                    Button("Open Login Items…") { LaunchAtLogin.openLoginItemsSettings() }
                } label: {
                    Label {
                        Text("Needs your approval")
                        Text("Allow Halo in System Settings › General › Login Items.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
        }
        .onAppear { status = LaunchAtLogin.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = LaunchAtLogin.status
        }
    }
}

// MARK: - Configuration

private struct ConfigurationSection: View {
    /// A file that parsed as a Halo configuration, waiting for the user to confirm the import.
    private struct PendingImport {
        var fileName: String
        var data: Data
    }

    @ViewState private var pendingImport: PendingImport?
    @ViewState private var isConfirmingReset = false
    @ViewState private var alert: PaneAlert?

    private var model: AppModel { .shared }

    // Dialogs hang off single rows: modifiers on a Section apply to each of its rows.
    var body: some View {
        Section {
            LabeledContent {
                HStack {
                    Button("Export…", action: export)
                    Button("Import…", action: chooseImport)
                }
            } label: {
                Text("Rings and settings")
                Text("Save everything to a .\(ConfigFile.exportExtension) file to back it up or move it to another Mac.")
            }
            .confirmationDialog(
                "Replace your rings and settings?",
                isPresented: Binding(isPresenting: $pendingImport),
                presenting: pendingImport
            ) { item in
                Button("Replace", role: .destructive) { apply(item) }
            } message: { item in
                Text("Everything in Halo, including app rings and the trigger shortcut, will be replaced with the contents of “\(item.fileName)”. You can undo this with ⌘Z.")
            }
            .alert(alert?.title ?? "", isPresented: Binding(isPresenting: $alert), presenting: alert) { _ in
                Button("OK") {}
            } message: { alert in
                Text(alert.message)
            }

            LabeledContent {
                Button("Show in Finder") { ConfigFileAccess.revealInFinder() }
            } label: {
                Text("Configuration file")
                Text(ConfigFileAccess.displayPath)
                    .textSelection(.enabled)
            }

            LabeledContent {
                Button("Reset to Defaults…", role: .destructive) { isConfirmingReset = true }
            } label: {
                Text("Reset")
                Text("Restores the default rings, removes app rings and resets appearance. Your shortcut is kept.")
            }
            .confirmationDialog("Reset Halo to its defaults?", isPresented: $isConfirmingReset) {
                Button("Reset to Defaults", role: .destructive) { model.resetToDefaults() }
            } message: {
                Text("Your rings, app rings, appearance and behavior settings go back to how Halo first started. Your trigger shortcut and login item are kept. You can undo this with ⌘Z.")
            }
        } header: {
            Text("Configuration")
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.title = "Export Halo Configuration"
        panel.prompt = "Export"
        panel.allowedContentTypes = ConfigFileAccess.contentTypes
        panel.nameFieldStringValue = "Halo Rings.\(ConfigFile.exportExtension)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        FilePanel.present(panel) { url in
            do {
                try AppModel.shared.exportData().write(to: url, options: .atomic)
                Log.config.info("Exported config to \(url.path, privacy: .public)")
            } catch {
                Log.config.error("Export failed: \(error.localizedDescription, privacy: .public)")
                alert = PaneAlert(title: "Couldn't Export", message: error.localizedDescription)
            }
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.title = "Import Halo Configuration"
        panel.prompt = "Import"
        panel.allowedContentTypes = ConfigFileAccess.contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        FilePanel.present(panel) { url in
            do {
                let data = try Data(contentsOf: url)
                // Check it before asking, so the user is never asked to replace with a bad file.
                _ = try ConfigFile.importConfig(from: data)
                pendingImport = PendingImport(fileName: url.lastPathComponent, data: data)
            } catch {
                Log.config.error("Import of \(url.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                alert = PaneAlert(title: "Couldn't Import “\(url.lastPathComponent)”", message: error.localizedDescription)
            }
        }
    }

    private func apply(_ item: PendingImport) {
        do {
            try model.importData(item.data)
            Log.config.info("Imported config from \(item.fileName, privacy: .public)")
        } catch {
            Log.config.error("Import failed: \(error.localizedDescription, privacy: .public)")
            alert = PaneAlert(title: "Couldn't Import “\(item.fileName)”", message: error.localizedDescription)
        }
    }
}
