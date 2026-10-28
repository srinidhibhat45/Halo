import AppKit
import HaloCore
import SwiftUI

/// Colour swatches: an optional "Default" swatch, the `RingColor` presets, and a custom colour
/// from the system colour panel (applied once the user stops dragging, so it is one undo step).
struct ColorSwatchPicker: View {
    @Binding private var selection: RingColor?
    private let allowsDefault: Bool
    private let defaultColor: Color
    private let defaultLabel: String

    @ViewState private var customDraft: Color?
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// A tint that can fall back to a default (nil).
    /// - Parameters:
    ///   - defaultColor: how the default swatch is drawn (e.g. the ring's accent colour).
    ///   - defaultLabel: its name for VoiceOver and the tooltip.
    init(selection: Binding<RingColor?>, defaultColor: Color = .accentColor, defaultLabel: String = "Default") {
        self._selection = selection
        self.allowsDefault = true
        self.defaultColor = defaultColor
        self.defaultLabel = defaultLabel
    }

    /// A colour that must always be set (no default swatch), e.g. the app-wide accent.
    init(color: Binding<RingColor>) {
        self._selection = Binding(
            get: { color.wrappedValue },
            set: { newValue in if let newValue { color.wrappedValue = newValue } }
        )
        self.allowsDefault = false
        self.defaultColor = .accentColor
        self.defaultLabel = "Default"
    }

    var body: some View {
        EditorFlowLayout(spacing: 7, lineSpacing: 7) {
            if allowsDefault {
                swatch(color: defaultColor, name: defaultLabel, isSelected: selection == nil, dashed: true) {
                    selection = nil
                }
            }
            ForEach(RingColor.Preset.allCases, id: \.self) { preset in
                let value = RingColor.preset(preset)
                swatch(color: value.color, name: value.name, isSelected: selection == value, dashed: false) {
                    selection = value
                }
            }
            ColorPicker("Custom Colour", selection: customBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Custom colour")
                .accessibilityLabel("Custom colour")
                .accessibilityAddTraits(isCustom ? .isSelected : [])
        }
        .accessibilityElement(children: .contain)
        .task(id: customDraft) {
            guard let draft = customDraft else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            selection = RingColor(NSColor(draft))
            customDraft = nil
        }
    }

    private var isCustom: Bool {
        if case .custom = selection { return true }
        return false
    }

    private var customBinding: Binding<Color> {
        Binding(
            get: { customDraft ?? (isCustom ? selection?.color : nil) ?? defaultColor },
            set: { customDraft = $0 }
        )
    }

    private func swatch(color: Color, name: String, isSelected: Bool, dashed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color.gradient)
                .frame(width: 20, height: 20)
                .overlay {
                    if dashed {
                        Circle().strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                            .padding(3)
                    }
                }
                .overlay(Circle().strokeBorder(.black.opacity(0.12)))
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(.primary, lineWidth: 2)
                            .padding(-4)
                        if differentiateWithoutColor {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
