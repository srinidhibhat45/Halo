import AppKit
import HaloCore
import SwiftUI

/// Draws an `IconSpec` at a given size: SF Symbol, app icon, custom image or emoji.
/// Empty (`nil`) draws a faint plus, used for empty slots.
struct IconView: View {
    let spec: IconSpec?
    var size: CGFloat
    /// Colour for SF Symbols (app icons, images and emoji keep their own colours).
    var symbolColor: Color = .primary
    /// Weight for SF Symbols.
    var weight: Font.Weight = .medium

    var body: some View {
        content
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch spec {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.78, weight: weight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolColor)
                .imageScale(.medium)
        case .app(let bundleID):
            Image(nsImage: AppCatalog.shared.icon(forBundleID: bundleID))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        case .image(let png):
            if let image = DecodedImageCache.shared.image(for: png) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: size * 0.7, weight: weight))
                    .foregroundStyle(symbolColor.opacity(0.6))
            }
        case .emoji(let text):
            Text(text)
                .font(.system(size: size * 0.8))
                .minimumScaleFactor(0.3)
                .lineLimit(1)
        case nil:
            Image(systemName: "plus")
                .font(.system(size: size * 0.55, weight: .regular))
                .foregroundStyle(symbolColor.opacity(0.35))
        }
    }
}

/// Decodes embedded PNG icons once.
final class DecodedImageCache {
    static let shared = DecodedImageCache()
    private let cache = NSCache<NSData, NSImage>()

    func image(for data: Data) -> NSImage? {
        let key = data as NSData
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

extension IconSpec {
    /// Renders any image file into ≤256 px PNG data suitable for `.image(png:)`.
    static func pngData(fromImageAt url: URL, maxPixels: CGFloat = 256) -> Data? {
        guard let source = NSImage(contentsOf: url) else { return nil }
        let size = source.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxPixels / max(size.width, size.height))
        let target = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
