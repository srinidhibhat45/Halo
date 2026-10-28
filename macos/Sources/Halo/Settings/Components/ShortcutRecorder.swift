import AppKit
import HaloCore
import SwiftUI

/// A click-to-record keyboard shortcut field.
///
/// Click to record; held modifiers show live as ⌃⌥⇧⌘ keycaps. Esc cancels, and clicking
/// elsewhere or leaving the window stops recording.
/// - `.trigger`: Delete clears. Combos `HotKeyCenter` rules out (no ⌘, ⌃ or ⌥, and not a
///   function key) are refused while recording continues; its warnings (⌥-only, standard macOS
///   and system shortcuts) show under the field, as do bare F1–F12 and a combo macOS refused to
///   register. The global trigger is suspended while recording.
/// - `.keystroke`: any key can be recorded, Return, Tab and Delete included.
struct ShortcutRecorder: View {
    enum Purpose {
        /// The global ring trigger: requires a modifier (or F-key) and suspends the current
        /// trigger while recording.
        case trigger
        /// A keystroke to send: any key, modifiers optional.
        case keystroke
    }

    @Binding var combo: KeyCombo?
    var purpose: Purpose = .keystroke

    @ViewState private var isRecording = false
    @ViewState private var liveModifiers: Modifiers = []
    @ViewState private var notice: RecorderNotice?
    @ViewState private var wasSuspended = false
    @Environment(\.shortcutRecorderStartRequest) private var startRequest
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(action: toggleRecording) { field }
                    .buttonStyle(.plain)
                    .background(RecorderEventBridge(isActive: isRecording, handler: handle))
                    .help(isRecording ? "Type the shortcut. Esc cancels." : "Click to record a shortcut")
                    .accessibilityLabel(isRecording ? "Recording shortcut" : "Shortcut")
                    .accessibilityValue(isRecording ? liveModifiers.names.joined(separator: " ") : combo?.accessibilityLabel ?? "None")
                    .accessibilityHint(isRecording ? hint : "Click to record a new shortcut.")
                if purpose == .trigger, combo != nil, !isRecording {
                    Button {
                        combo = nil
                        notice = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear the shortcut")
                    .accessibilityLabel("Clear shortcut")
                }
            }
            if let notice, notice.isError || !isRecording {
                notice.label
            } else if isRecording {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { notice = Self.warning(for: combo, purpose: purpose) }
        .onChange(of: startRequest?.wrappedValue ?? false, initial: true) { _, requested in
            guard requested else { return }
            startRequest?.wrappedValue = false
            beginRecording()
        }
        .onDisappear(perform: endRecording)
        .onChange(of: combo) { _, newValue in
            if !isRecording { notice = Self.warning(for: newValue, purpose: purpose) }
        }
    }

    private var hint: String {
        switch purpose {
        case .trigger: "Press the new shortcut. Esc cancels, Delete clears."
        case .keystroke: "Press the keys to send. Esc cancels."
        }
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: 3) {
            if isRecording {
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    .accessibilityHidden(true)
                if liveModifiers.isEmpty {
                    Text("Type Shortcut…")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Self.glyphs(for: liveModifiers), id: \.self) { RecorderKeycap(text: $0) }
                }
            } else if let combo {
                ForEach(Self.glyphs(for: combo.modifiers), id: \.self) { RecorderKeycap(text: $0) }
                RecorderKeycap(text: combo.keyLabel)
            } else {
                Text("Record Shortcut")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(minWidth: 150, minHeight: 22)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isRecording ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isRecording ? 2 : 1)
        }
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Rectangle())
    }

    // MARK: Recording

    private func toggleRecording() {
        if isRecording { endRecording() } else { beginRecording() }
    }

    private func beginRecording() {
        guard !isRecording, isEnabled else { return }
        notice = nil
        liveModifiers = []
        if purpose == .trigger {
            wasSuspended = HotKeyCenter.shared.isSuspended
            HotKeyCenter.shared.isSuspended = true
        }
        isRecording = true
        AccessibilityNotification.Announcement("Recording. \(hint)").post()
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        liveModifiers = []
        // A refused attempt was never saved; show what the saved combo deserves instead.
        if notice?.isError == true { notice = Self.warning(for: combo, purpose: purpose) }
        if purpose == .trigger { HotKeyCenter.shared.isSuspended = wasSuspended }
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: RecorderEvent) -> Bool {
        switch event {
        case .modifiers(let flags):
            liveModifiers = Modifiers(flags).subtracting(.function)
            return false
        case .dismiss:
            endRecording()
            return false
        case .key(let keyEvent):
            return record(keyEvent)
        }
    }

    private func record(_ event: NSEvent) -> Bool {
        var recorded = KeyboardLayout.combo(from: event)
        if purpose == .trigger || Self.functionRowKeys.contains(recorded.keyCode) {
            recorded.modifiers.remove(.function)
        }
        if recorded.modifiers.isEmpty {
            switch recorded.keyCode {
            case KeyCode.escape:
                endRecording()
                return true
            case KeyCode.delete, KeyCode.forwardDelete:
                if purpose == .trigger {
                    combo = nil
                    notice = nil
                    endRecording()
                    return true
                }
            case KeyCode.tab:
                if purpose == .trigger {
                    endRecording()
                    return false
                }
            default:
                break
            }
        }
        if purpose == .trigger, let problem = Self.triggerProblem(recorded) {
            NSSound.beep()
            notice = .error(problem)
            return true
        }
        combo = recorded
        endRecording()
        notice = Self.warning(for: recorded, purpose: purpose)
        AccessibilityNotification.Announcement("Recorded \(recorded.accessibilityLabel)").post()
        if purpose == .trigger { verifyRegistration(of: recorded) }
        return true
    }

    /// After the new trigger reaches the settings and the trigger resumes, check that macOS
    /// registered it.
    private func verifyRegistration(of recorded: KeyCombo) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            let hotKeys = HotKeyCenter.shared
            guard combo == recorded, !isRecording, AppModel.shared.settings.trigger == recorded,
                  hotKeys.registeredTrigger != recorded else { return }
            notice = .warning(hotKeys.lastRegistrationError ?? "macOS didn't accept this shortcut. Another app may already be using it.")
        }
    }

    // MARK: Rules

    /// Keys that macOS reports with the Fn flag set even when Fn isn't held.
    private static let functionRowKeys: Set<UInt16> = Set(functionKeys).union([
        KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.upArrow, KeyCode.downArrow, KeyCode.forwardDelete,
        0x73, 0x77, 0x74, 0x79, 0x72, // Home, End, Page Up, Page Down, Help
    ])

    private static let functionKeys: [UInt16] = [
        KeyCode.f1, KeyCode.f2, KeyCode.f3, KeyCode.f4, KeyCode.f5, KeyCode.f6, KeyCode.f7, KeyCode.f8, KeyCode.f9, KeyCode.f10,
        KeyCode.f11, KeyCode.f12, KeyCode.f13, KeyCode.f14, KeyCode.f15, KeyCode.f16, KeyCode.f17, KeyCode.f18, KeyCode.f19, KeyCode.f20,
    ]

    /// Why `combo` can't be the trigger, or nil if it can.
    static func triggerProblem(_ combo: KeyCombo) -> String? {
        if case .invalid(let reason)? = HotKeyCenter.problem(for: combo) { return reason }
        return nil
    }

    /// A caution worth showing for an accepted combo.
    static func warning(for combo: KeyCombo?, purpose: Purpose) -> RecorderNotice? {
        guard let combo else { return nil }
        switch purpose {
        case .trigger:
            if case .warning(let caution)? = HotKeyCenter.problem(for: combo) { return .warning(caution) }
            if combo.modifiers.isEmpty, functionKeys.prefix(12).contains(combo.keyCode) {
                return .warning("On Mac keyboards, \(combo.keyLabel) adjusts brightness or volume unless you hold fn. Mouse software can send it directly.")
            }
            return nil
        case .keystroke:
            if let trigger = AppModel.shared.settings.trigger, trigger.keyCode == combo.keyCode,
               trigger.modifiers.subtracting(.function) == combo.modifiers.subtracting(.function) {
                return .warning("This is Halo's trigger, so sending it opens the ring again.")
            }
            return nil
        }
    }

    private static func glyphs(for modifiers: Modifiers) -> [String] {
        var glyphs: [String] = []
        if modifiers.contains(.function) { glyphs.append("fn") }
        if modifiers.contains(.control) { glyphs.append("⌃") }
        if modifiers.contains(.option) { glyphs.append("⌥") }
        if modifiers.contains(.shift) { glyphs.append("⇧") }
        if modifiers.contains(.command) { glyphs.append("⌘") }
        return glyphs
    }
}

/// An error (combo rejected, still recording) or warning (combo accepted) under the field.
enum RecorderNotice: Equatable {
    case error(String)
    case warning(String)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var label: some View {
        let (text, symbol, color): (String, String, Color) = switch self {
        case .error(let text): (text, "xmark.octagon.fill", .red)
        case .warning(let text): (text, "exclamationmark.triangle.fill", .orange)
        }
        return Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One key or modifier glyph.
private struct RecorderKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 18)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Start request

private struct RecorderStartRequestKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    /// When the bound value becomes true, recorders below start recording and reset it.
    var shortcutRecorderStartRequest: Binding<Bool>? {
        get { self[RecorderStartRequestKey.self] }
        set { self[RecorderStartRequestKey.self] = newValue }
    }
}

extension View {
    /// Starts recording in the `ShortcutRecorder`s below when `request` becomes true (e.g. right
    /// after the user added a "Keyboard Shortcut…" action), then resets it.
    func shortcutRecorderStartRequest(_ request: Binding<Bool>) -> some View {
        environment(\.shortcutRecorderStartRequest, request)
    }
}

// MARK: - Event capture

private enum RecorderEvent {
    case key(NSEvent)
    case modifiers(NSEvent.ModifierFlags)
    /// A click outside the field or the window losing focus.
    case dismiss
}

/// Watches key and mouse events while recording through a local event monitor; sits behind the
/// field so it knows the field's bounds.
private struct RecorderEventBridge: NSViewRepresentable {
    var isActive: Bool
    var handler: (RecorderEvent) -> Bool

    func makeNSView(context: Context) -> RecorderEventView { RecorderEventView() }

    func updateNSView(_ view: RecorderEventView, context: Context) {
        view.handler = handler
        view.setActive(isActive)
    }

    static func dismantleNSView(_ view: RecorderEventView, coordinator: ()) {
        view.setActive(false)
    }
}

private final class RecorderEventView: NSView {
    var handler: ((RecorderEvent) -> Bool)?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    /// Clicks go to the SwiftUI button on top.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setActive(_ active: Bool) {
        if active, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self else { return event }
                return self.process(event) ? nil : event
            }
            if let window {
                resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { _ = self?.handler?(.dismiss) }
                }
            }
        } else if !active, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            if let resignObserver {
                NotificationCenter.default.removeObserver(resignObserver)
                self.resignObserver = nil
            }
        }
    }

    /// Returns true to swallow the event.
    private func process(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            guard event.window === window else { return false }
            return handler?(.key(event)) ?? false
        case .flagsChanged:
            _ = handler?(.modifiers(event.modifierFlags))
            return false
        default:
            let inside = event.window === window && bounds.contains(convert(event.locationInWindow, from: nil))
            if !inside { _ = handler?(.dismiss) }
            return false
        }
    }
}
