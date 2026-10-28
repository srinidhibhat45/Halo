import HaloCore
import SwiftUI

/// Step 4: open the real ring and learn the moves that suit the chosen selection mode.
struct OnboardingTryItPage: View {
    private struct Tip: Identifiable {
        var symbol: String
        var title: String
        var detail: String
        var id: String { title }
    }

    var body: some View {
        let settings = AppModel.shared.settings
        VStack(spacing: 16) {
            OnboardingHeader(
                symbol: "hand.tap",
                title: "Try It",
                subtitle: settings.trigger.map { "Press \($0.displayString) anywhere, or open the ring here." }
                    ?? "Open the ring here, or record a shortcut to open it anywhere."
            )
            Button {
                OverlayController.shared.presentForTesting()
            } label: {
                Label("Show the Ring", systemImage: "circle.dotted.circle")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                let tips = Self.tips(for: settings.selectionMode)
                ForEach(0..<(tips.count / 2), id: \.self) { row in
                    GridRow {
                        tipCard(tips[row * 2])
                        tipCard(tips[row * 2 + 1])
                    }
                }
            }
            Text("Actions run in the app in front, so the real test is in another app.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tipCard(_ tip: Tip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.symbol)
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title).font(.headline)
                Text(tip.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onboardingCard()
        .accessibilityElement(children: .combine)
    }

    /// Two gesture tips for the mode, then the keyboard and closing tips every mode shares.
    private static func tips(for mode: SelectionMode) -> [Tip] {
        let tap = Tip(symbol: "cursorarrow.click.2", title: "Tap, then click",
                      detail: "Press your shortcut once. The ring stays open until you click an action.")
        let flick = Tip(symbol: "hand.draw", title: "Hold, flick, release",
                        detail: "Hold the button, move toward an action and let go. Flicks work even before the ring appears.")
        let again = Tip(symbol: "arrow.clockwise.circle", title: "Press again to run",
                        detail: "Point at an action and press your shortcut again to run it.")
        let cancel = Tip(symbol: "arrow.uturn.backward.circle", title: "Changed your mind?",
                         detail: "Let go in the centre and nothing runs.")
        let keys = Tip(symbol: "number", title: "Keys work too",
                       detail: "Press 1–9 to run a slot directly. Arrows or Tab move the highlight; Return runs it.")
        let close = Tip(symbol: "escape", title: "Close any time",
                        detail: "Press Esc, click outside or click the centre. In a nested ring, Esc goes back.")
        let gestures = switch mode {
        case .auto: [tap, flick]
        case .tapThenClick: [tap, again]
        case .holdAndRelease: [flick, cancel]
        }
        return gestures + [keys, close]
    }
}
