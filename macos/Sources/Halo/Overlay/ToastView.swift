import Observation
import SwiftUI

/// What a toast shows.
struct ToastContent {
    var message: String
    var symbol: String
    var tint: Color
    var buttonTitle: String?
}

/// Live state of the toast panel, driven by `ToastPresenter`.
@Observable
final class ToastModel {
    /// Drives the spring in (true) and fade out (false).
    var isVisible = false
    /// The pointer went down on the button and is still over it.
    var isButtonPressed = false
    /// The button's frame in the hosting view (y-down), for hit-testing clicks in AppKit.
    @ObservationIgnored var buttonFrame: CGRect?
    /// Runs the button (VoiceOver and keyboard presses; pointer clicks are routed by the panel).
    @ObservationIgnored var onButton: (() -> Void)?
}

/// A Liquid Glass capsule with an SF Symbol, a message and an optional button.
struct ToastView: View {
    let content: ToastContent
    let model: ToastModel

    /// Room around the capsule for its shadow and the spring's overshoot.
    static let margin: CGFloat = 14
    nonisolated static let coordinateSpace = "HaloToast"

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        capsule
            .padding(Self.margin)
            .scaleEffect(model.isVisible || reduceMotion ? 1 : 0.86)
            .offset(y: model.isVisible || reduceMotion ? 0 : -6)
            .opacity(model.isVisible ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.72), value: model.isVisible)
            .coordinateSpace(.named(Self.coordinateSpace))
            .environment(\.appearsActive, true)
    }

    private var capsule: some View {
        HStack(spacing: 10) {
            Image(systemName: content.symbol)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(content.tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(content.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let title = content.buttonTitle {
                Button(title) { model.onButton?() }
                    .buttonStyle(ToastButtonStyle(tint: content.tint, isPressed: model.isButtonPressed, highContrast: contrast == .increased))
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(ToastView.coordinateSpace))
                    } action: { frame in
                        model.buttonFrame = frame
                    }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, content.buttonTitle == nil ? 18 : 6)
        .padding(.vertical, 7)
        .frame(minHeight: 38)
        .modifier(ToastChrome(reduceTransparency: reduceTransparency, highContrast: contrast == .increased))
        .accessibilityElement(children: .contain)
    }
}

/// Liquid Glass, or an opaque capsule with Reduce Transparency; outlined with Increase Contrast.
private struct ToastChrome: ViewModifier {
    let reduceTransparency: Bool
    let highContrast: Bool

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content
                    .background(Capsule(style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            } else {
                content.glassEffect(.regular, in: Capsule(style: .continuous))
            }
        }
        .overlay {
            if highContrast {
                Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
            } else if reduceTransparency {
                Capsule(style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
    }
}

/// A small tinted capsule button. `isPressed` mirrors the AppKit-tracked press.
private struct ToastButtonStyle: ButtonStyle {
    let tint: Color
    let isPressed: Bool
    let highContrast: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = isPressed || configuration.isPressed
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(tint.opacity(pressed ? 0.4 : 0.2)))
            .overlay {
                if highContrast { Capsule(style: .continuous).strokeBorder(tint, lineWidth: 1) }
            }
            .contentShape(Capsule(style: .continuous))
    }
}
