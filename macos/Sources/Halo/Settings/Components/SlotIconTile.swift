import HaloCore
import SwiftUI

/// An icon on a soft rounded tile (SF Symbols and emoji), or bare (app icons and images, which
/// carry their own shape). Used in the library, inspector and pickers.
struct SlotIconTile: View {
    let icon: IconSpec?
    var size: CGFloat = 28
    var tint: Color = .accentColor

    var body: some View {
        switch icon {
        case .app, .image:
            IconView(spec: icon, size: size)
        default:
            IconView(spec: icon, size: size * 0.6, symbolColor: tint)
                .frame(width: size, height: size)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        }
    }
}
