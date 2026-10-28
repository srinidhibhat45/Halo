import HaloCore
import SwiftUI

/// A page's centred title block: an optional symbol tile, the title and a short explanation.
struct OnboardingHeader: View {
    var symbol: String?
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 52, height: 52)
                    .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The guide's rounded card: a quiet fill with a hairline edge that strengthens with Increase
/// Contrast.
private struct OnboardingCardStyle: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .padding(16)
            .background(.fill.quaternary, in: shape)
            .overlay {
                shape.strokeBorder(contrast == .increased ? AnyShapeStyle(.primary.opacity(0.45)) : AnyShapeStyle(.separator),
                                   lineWidth: contrast == .increased ? 1 : 0.5)
            }
    }
}

extension View {
    /// Wraps the view in the guide's card style.
    func onboardingCard() -> some View {
        modifier(OnboardingCardStyle())
    }
}

/// Page indicator: one dot per step, the current one drawn as a wider accent capsule. Each dot is
/// a button that jumps to its step.
struct OnboardingPageDots: View {
    let current: OnboardingPage
    let select: (OnboardingPage) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 2) {
            ForEach(OnboardingPage.allCases) { page in
                let isCurrent = page == current
                Button { select(page) } label: {
                    Capsule()
                        .fill(isCurrent ? AnyShapeStyle(.tint) : idleStyle)
                        .frame(width: isCurrent ? 22 : 8, height: 8)
                        .padding(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(page.title)
                .accessibilityLabel(page.spokenPosition)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: current)
    }

    private var idleStyle: AnyShapeStyle {
        contrast == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
    }
}

/// A shortcut drawn as keyboard keys: ⌃ ⇧ ⌘ H.
struct OnboardingKeyCaps: View {
    let combo: KeyCombo

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .frame(minWidth: 24, minHeight: 24)
                    .padding(.horizontal, key.count > 1 ? 6 : 0)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo.accessibilityLabel)
    }

    /// Each modifier as its own key, in Apple's order, then the key itself.
    private var keys: [String] {
        let modifiers: [(Modifiers, String)] = [(.function, "fn"), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return modifiers.filter { combo.modifiers.contains($0.0) }.map(\.1) + [combo.keyLabel]
    }
}

/// One numbered instruction.
struct OnboardingStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 18, height: 18)
                .background(.tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}
