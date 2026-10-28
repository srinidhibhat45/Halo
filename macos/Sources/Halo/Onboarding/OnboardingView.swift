import AppKit
import HaloCore
import SwiftUI

/// The steps of the first-run guide, in order.
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome, shortcut, permissions, tryIt, done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .shortcut: "Your Shortcut"
        case .permissions: "Permissions"
        case .tryIt: "Try It"
        case .done: "All Set"
        }
    }

    /// "Step 2 of 5: Your Shortcut", for VoiceOver.
    var spokenPosition: String {
        "Step \(rawValue + 1) of \(Self.allCases.count): \(title)"
    }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }
}

/// First-run guide (SPEC §4): welcome, shortcut and mouse button, permissions, try it, done.
/// Opens at first launch and from the menu bar's "Welcome Guide…".
struct OnboardingView: View {
    /// The guide window's content size (fixed).
    static let preferredSize = CGSize(width: 760, height: 580)

    @ViewState private var page: OnboardingPage = .welcome
    /// Direction of the latest page change, for the slide transition.
    @ViewState private var movesForward = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                pageContent(page)
                    .id(page)
                    .transition(pageTransition)
            }
            .padding(.horizontal, 44)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backdrop)
        .onChange(of: page) { _, newPage in
            AccessibilityNotification.Announcement(newPage.spokenPosition).post()
        }
    }

    @ViewBuilder
    private func pageContent(_ page: OnboardingPage) -> some View {
        switch page {
        case .welcome: OnboardingWelcomePage()
        case .shortcut: OnboardingShortcutPage()
        case .permissions: OnboardingPermissionsPage()
        case .tryIt: OnboardingTryItPage()
        case .done: OnboardingDonePage(customizeRing: { finish(openingSettings: true) })
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 0) {
            HStack {
                if let previous = page.previous {
                    Button("Back") { go(to: previous) }
                        .keyboardShortcut(.cancelAction)
                        .help("Go back to \(previous.title)")
                }
                Spacer(minLength: 0)
            }
            .frame(width: Self.footerSideWidth)

            Spacer(minLength: 0)
            OnboardingPageDots(current: page) { go(to: $0) }
            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                Button(continueTitle) {
                    if let next = page.next { go(to: next) } else { finish(openingSettings: false) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .frame(width: Self.footerSideWidth)
        }
        .controlSize(.large)
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    /// Equal widths on both sides keep the page dots centred.
    private static let footerSideWidth: CGFloat = 180

    private var continueTitle: String {
        switch page {
        case .welcome: "Get Started"
        case .done: "Start Using Halo"
        default: "Continue"
        }
    }

    // MARK: Navigation

    private func go(to target: OnboardingPage) {
        guard target != page else { return }
        movesForward = target.rawValue > page.rawValue
        // The outgoing page keeps the transition it was last rendered with, so let it pick up the
        // new direction before the animated change.
        Task { @MainActor in
            withAnimation(pageAnimation) { page = target }
        }
    }

    private func finish(openingSettings: Bool) {
        OnboardingFlow.markCompleted()
        WindowCoordinator.shared.close(.onboarding)
        if openingSettings { SettingsRouter.shared.open(.ring(.global)) }
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.4)
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let shift: CGFloat = 56
        return .asymmetric(
            insertion: .offset(x: movesForward ? shift : -shift).combined(with: .opacity),
            removal: .offset(x: movesForward ? -shift : shift).combined(with: .opacity)
        )
    }

    // MARK: Background

    /// The window colour with a soft glow of the ring's accent from the top.
    private var backdrop: some View {
        let accent = AppModel.shared.settings.accent.color
        return ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [accent.opacity(contrast == .increased ? 0.08 : 0.16), .clear],
                center: .top,
                startRadius: 0,
                endRadius: Self.preferredSize.width * 0.7
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Bookkeeping shared by the guide and its window.
enum OnboardingFlow {
    /// Records that the guide has been seen, so it doesn't open again at launch. Not undoable:
    /// it is bookkeeping, not an edit.
    static func markCompleted() {
        guard !AppModel.shared.settings.hasCompletedOnboarding else { return }
        AppModel.shared.updateSettingsOutsideUndo { $0.hasCompletedOnboarding = true }
    }

    /// The guide's window closed, finished or not: hand the trigger back to the ring and don't
    /// open the guide at launch again (it stays in the menu bar menu).
    static func windowDidClose() {
        TriggerProbe.stopListening()
        markCompleted()
    }

    /// Short names for selection modes, as the guide uses them.
    static func name(of mode: SelectionMode) -> String {
        switch mode {
        case .auto: "Automatic"
        case .tapThenClick: "Tap, Then Click"
        case .holdAndRelease: "Hold and Release"
        }
    }
}
