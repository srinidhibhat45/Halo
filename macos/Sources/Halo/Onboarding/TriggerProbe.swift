import HaloCore
import Observation
import SwiftUI

/// "Test your trigger": measures how long one trigger press stays down, to tell whether the
/// user's mouse software holds the keys while the button is held (hold-and-release works) or
/// sends an instant tap (use tap, then click).
///
/// While listening, `OverlayController.calibration` receives trigger presses instead of the ring.
@Observable
final class TriggerProbe {
    enum Phase: Equatable {
        case idle
        case listening
        /// One press was measured: it lasted this many seconds.
        case measured(TimeInterval)
    }

    enum Verdict {
        /// The keys stayed down while the button was held.
        case holds
        /// The software sent a tap however long the button was held.
        case taps
        /// Too short to be a deliberate hold, too long to be a synthetic tap.
        case unclear
    }

    /// Presses shorter than this are synthetic taps; nobody holds a button for less.
    static let tapLimit: TimeInterval = 0.12
    /// Presses at least this long mean the keys stay down while the button is held.
    static let holdMinimum: TimeInterval = 0.5

    private(set) var phase: Phase = .idle

    /// True while a probe's handler is installed, so stopping never removes another
    /// calibration (such as the General pane's).
    private static var isInstalled = false

    func start() {
        phase = .listening
        Self.isInstalled = true
        OverlayController.shared.calibration = { [weak self] seconds in
            guard let self else {
                // The view that started the test is gone; give the trigger back to the ring.
                Self.stopListening()
                return
            }
            self.record(seconds)
        }
        Log.trigger.info("Trigger test started")
    }

    func cancel() {
        guard phase == .listening else { return }
        Self.stopListening()
        phase = .idle
    }

    private func record(_ seconds: TimeInterval) {
        Self.stopListening()
        phase = .measured(seconds)
        Log.trigger.info("Trigger test measured a \(seconds, format: .fixed(precision: 3), privacy: .public) s press")
    }

    /// Hands trigger presses back to the ring, if a probe has them.
    static func stopListening() {
        guard isInstalled else { return }
        isInstalled = false
        OverlayController.shared.calibration = nil
    }

    static func verdict(for seconds: TimeInterval) -> Verdict {
        if seconds >= holdMinimum { return .holds }
        if seconds < tapLimit { return .taps }
        return .unclear
    }

    /// The selection mode that suits a verdict, or nil when the test should be repeated.
    static func recommendedMode(for verdict: Verdict) -> SelectionMode? {
        switch verdict {
        case .holds: .auto
        case .taps: .tapThenClick
        case .unclear: nil
        }
    }
}

/// The "Test your trigger" card: start, hold the button, read the verdict, adopt the suggested
/// selection mode.
struct TriggerProbeCard: View {
    @ViewState private var probe = TriggerProbe()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Test your trigger", systemImage: "stopwatch")
                .font(.headline)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .onDisappear { probe.cancel() }
        .onChange(of: probe.phase) { _, phase in
            if case .measured(let seconds) = phase {
                AccessibilityNotification.Announcement(Self.headline(for: TriggerProbe.verdict(for: seconds))).post()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if AppModel.shared.settings.trigger == nil {
            explanation("Record a shortcut first, then come back to test it.")
        } else if HotKeyCenter.shared.registeredTrigger != AppModel.shared.settings.trigger {
            explanation("This shortcut isn't active (another app may be using it). Record a different one, then test it.")
        } else {
            switch probe.phase {
            case .idle:
                explanation("Hold your mouse button (or the shortcut) for about a second, then let go. Halo checks whether your software holds the keys down.")
                Button("Start Test") { probe.start() }
            case .listening:
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.tint)
                        .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                        .accessibilityHidden(true)
                    Text("Hold the button now…")
                        .font(.callout.weight(.medium))
                }
                explanation("The ring won't open during the test.")
                Button("Cancel") { probe.cancel() }
            case .measured(let seconds):
                result(seconds)
            }
        }
    }

    @ViewBuilder
    private func result(_ seconds: TimeInterval) -> some View {
        let verdict = TriggerProbe.verdict(for: seconds)
        let duration = seconds.formatted(.number.precision(.fractionLength(2)))
        Label(Self.headline(for: verdict), systemImage: verdict == .unclear ? "questionmark.circle.fill" : "checkmark.circle.fill")
            .font(.callout.weight(.semibold))
            .foregroundStyle(verdict == .unclear ? AnyShapeStyle(.orange) : AnyShapeStyle(.green))
        switch verdict {
        case .holds:
            explanation("The press lasted \(duration) s, so hold, flick and release works. Automatic also lets you tap to keep the ring open.")
        case .taps:
            explanation("Halo saw a \(duration) s tap: your software doesn't hold the keys down. Use Tap, Then Click: press once, then click an action.")
        case .unclear:
            explanation("That press lasted \(duration) s. Hold the button for a full second so Halo can tell.")
        }
        HStack {
            if let mode = TriggerProbe.recommendedMode(for: verdict) {
                if AppModel.shared.settings.selectionMode == mode {
                    Label("Using \(OnboardingFlow.name(of: mode))", systemImage: "checkmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Use \(OnboardingFlow.name(of: mode))") {
                        AppModel.shared.updateSettings("Change Selection Mode") { $0.selectionMode = mode }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Button("Test Again") { probe.start() }
        }
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func headline(for verdict: TriggerProbe.Verdict) -> String {
        switch verdict {
        case .holds: "Hold and release works"
        case .taps: "Your software sends a tap"
        case .unclear: "Hold a little longer"
        }
    }
}
