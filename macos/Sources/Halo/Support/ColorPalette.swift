import AppKit
import HaloCore
import SwiftUI

extension RingColor {
    var nsColor: NSColor {
        switch self {
        case .preset(let p): p.nsColor
        case .custom(let r, let g, let b): NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Display name for pickers and VoiceOver.
    var name: String {
        switch self {
        case .preset(let p): p.rawValue.capitalized
        case .custom: "Custom"
        }
    }

    /// Builds a custom colour from any NSColor (e.g. a ColorPicker result).
    init(_ nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? .systemBlue
        self = .custom(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
    }
}

extension RingColor.Preset {
    var nsColor: NSColor {
        switch self {
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .cyan: .systemCyan
        case .brown: .systemBrown
        case .graphite: .systemGray
        }
    }
}
