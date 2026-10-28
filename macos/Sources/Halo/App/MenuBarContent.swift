import AppKit
import HaloCore
import SwiftUI

/// The menu bar extra's menu. Every item is a `Label` with `.titleAndIcon`, which macOS 27
/// needs to keep showing menu icons.
struct MenuBarContent: View {
    var body: some View {
        let model = AppModel.shared

        Button {
            OverlayController.shared.presentForTesting()
        } label: {
            Label("Show Ring", systemImage: "circle.dotted.circle")
                .labelStyle(.titleAndIcon)
        }
        // Shows the trigger next to the item, so the menu teaches the shortcut.
        .keyboardShortcut(Self.menuShortcut(for: model.settings.trigger))

        Button {
            SettingsRouter.shared.open()
        } label: {
            Label("Halo Settings…", systemImage: "gearshape")
                .labelStyle(.titleAndIcon)
        }
        .keyboardShortcut(",")

        Button {
            model.isPaused.toggle()
            Log.app.info("Halo \(model.isPaused ? "paused" : "resumed", privacy: .public)")
        } label: {
            if model.isPaused {
                Label("Resume Halo", systemImage: "play.circle")
                    .labelStyle(.titleAndIcon)
            } else {
                Label("Pause Halo", systemImage: "pause.circle")
                    .labelStyle(.titleAndIcon)
            }
        }

        Button {
            SettingsRouter.shared.openOnboarding()
        } label: {
            Label("Welcome Guide…", systemImage: "hand.wave")
                .labelStyle(.titleAndIcon)
        }

        let updates = UpdateController.shared
        if let version = updates.availableVersion {
            Button {
                Task { await updates.installAvailableUpdate() }
            } label: {
                Label("Install Halo \(version.description)…", systemImage: "arrow.down.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
        } else {
            Button {
                Task { await updates.check(userInitiated: true) }
            } label: {
                Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(updates.isBusy)
        }

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Quit Halo", systemImage: "power")
                .labelStyle(.titleAndIcon)
        }
        .keyboardShortcut("q")
    }

    /// The trigger as a menu key equivalent, or nil when its key has no single-character
    /// equivalent (F-keys, Space, arrows…).
    private static func menuShortcut(for combo: KeyCombo?) -> KeyboardShortcut? {
        guard let combo, combo.keyLabel.count == 1, let character = combo.keyLabel.lowercased().first,
              character.isLetter || character.isNumber || character.isPunctuation
        else { return nil }
        var modifiers: EventModifiers = []
        if combo.modifiers.contains(.control) { modifiers.insert(.control) }
        if combo.modifiers.contains(.option) { modifiers.insert(.option) }
        if combo.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if combo.modifiers.contains(.command) { modifiers.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }
}
