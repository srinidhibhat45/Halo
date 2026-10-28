import AppKit
import HaloCore
import SwiftUI
import UniformTypeIdentifiers

/// SF Symbols that stand for Halo itself.
enum HaloSymbol {
    /// The Halo glyph: a ring around a hub. Used for the Everywhere ring.
    static let ring = "circle.circle"
}

// MARK: - Bindings

extension Binding {
    /// Reads and writes one field of `AppModel.shared.settings`. Every write is one undoable
    /// step named `actionName`.
    static func appSetting(_ keyPath: WritableKeyPath<AppSettings, Value> & Sendable, _ actionName: String) -> Binding<Value> {
        Binding {
            AppModel.shared.settings[keyPath: keyPath]
        } set: { newValue in
            AppModel.shared.updateSettings(actionName) { $0[keyPath: keyPath] = newValue }
        }
    }
}

extension Binding where Value == Bool {
    /// True while `optional` holds a value; setting false clears it. Drives alerts and dialogs
    /// that present an item.
    init<Wrapped>(isPresenting optional: Binding<Wrapped?>) {
        self.init {
            optional.wrappedValue != nil
        } set: { isPresented in
            if !isPresented { optional.wrappedValue = nil }
        }
    }
}

/// Glue for a slider that previews live while dragging but saves once, on release, so one drag
/// is one undo step and one save. Keyboard and VoiceOver adjustments, which don't drag, save
/// immediately.
///
/// The view owns `draft` (`@ViewState var draft: Double?`): it is non-nil while dragging, so
/// previews can show `draft ?? saved`.
struct DeferredSliderValue {
    /// The saved value.
    let saved: Double
    let draft: Binding<Double?>
    let commit: @MainActor (Double) -> Void

    /// Bind the slider's `value` to this.
    var value: Binding<Double> {
        let saved = saved
        let draft = draft
        let commit = commit
        return Binding {
            draft.wrappedValue ?? saved
        } set: { newValue in
            if draft.wrappedValue != nil {
                draft.wrappedValue = newValue
            } else {
                commit(newValue)
            }
        }
    }

    /// Pass to the slider's `onEditingChanged`.
    func editingChanged(_ isEditing: Bool) {
        if isEditing {
            draft.wrappedValue = draft.wrappedValue ?? saved
        } else if let final = draft.wrappedValue {
            draft.wrappedValue = nil
            commit(final)
        }
    }
}

// MARK: - Configuration file

/// File types and Finder helpers for Halo's configuration.
enum ConfigFileAccess {
    /// `.haloring` (a JSON document), then plain `.json`.
    static var contentTypes: [UTType] {
        let haloring = UTType(filenameExtension: ConfigFile.exportExtension, conformingTo: .json)
        return [haloring, .json].compactMap { $0 }
    }

    /// `~/Library/Application Support/Halo/config.json`, abbreviated with a tilde.
    static var displayPath: String {
        (ConfigFile.defaultURL.path as NSString).abbreviatingWithTildeInPath
    }

    /// Selects `config.json` in Finder, saving it first if Halo hasn't written it yet.
    static func revealInFinder() {
        let fm = FileManager.default
        let url = ConfigFile.defaultURL
        if !fm.fileExists(atPath: url.path) { AppModel.shared.flush() }
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if fm.fileExists(atPath: ConfigFile.directory.path) {
            NSWorkspace.shared.open(ConfigFile.directory)
        } else {
            Log.config.error("No config folder to show at \(ConfigFile.directory.path, privacy: .public)")
            NSSound.beep()
        }
    }
}

/// Presents open and save panels as a sheet on the key window (the settings window or its
/// sheet), falling back to a free-standing panel.
enum FilePanel {
    /// Calls `handle` with the chosen URL; does nothing when the user cancels.
    static func present(_ panel: NSSavePanel, then handle: @escaping @MainActor (URL) -> Void) {
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            handle(url)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}

/// A titled message for an `.alert`.
struct PaneAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

// MARK: - Small views

/// A coloured capsule with a symbol and a word or two: "Allowed", "Ready", "Off"…
struct StatusBadge: View {
    enum Tone {
        case positive, caution, negative, neutral

        var color: Color {
            switch self {
            case .positive: .green
            case .caution: .orange
            case .negative: .red
            case .neutral: .secondary
            }
        }
    }

    let title: String
    let symbol: String
    let tone: Tone

    init(_ title: String, symbol: String, tone: Tone) {
        self.title = title
        self.symbol = symbol
        self.tone = tone
    }

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tone.color.opacity(0.14), in: Capsule())
            .overlay {
                if contrast == .increased {
                    Capsule().strokeBorder(tone.color, lineWidth: 1)
                }
            }
            .fixedSize()
    }
}

/// A key drawn like a keyboard key, for shortcut hints ("⌘", "Tab", "1").
struct KeyCap: View {
    let text: String

    init(_ text: String) { self.text = text }

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: 24)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(contrast == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(.separator), lineWidth: 1)
            }
            .fixedSize()
    }
}

/// A soft, wallpaper-like backdrop for ring previews, so the Glass theme has something to
/// refract and the Classic theme is seen against a desktop, as it will be in use.
struct PreviewBackdrop: View {
    var cornerRadius: CGFloat = 14

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = colorScheme == .dark
        shape
            .fill(LinearGradient(
                colors: [
                    Color(nsColor: .systemTeal).opacity(dark ? 0.45 : 0.55),
                    Color(nsColor: .systemIndigo).opacity(dark ? 0.55 : 0.45),
                    Color(nsColor: .systemPink).opacity(dark ? 0.35 : 0.4),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .background(dark ? Color.black : Color.white, in: shape)
            .overlay {
                shape.strokeBorder(contrast == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(.separator), lineWidth: 1)
            }
    }
}
