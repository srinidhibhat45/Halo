import AppKit
import HaloCore
import SwiftUI

/// What every pre-rendered Classic image depends on besides what it shows.
struct ClassicArtStyle: Hashable {
    /// The ring's size multiplier (Medium = 1).
    var unit: CGFloat
    /// Device pixels per point of the display the ring is on.
    var pixelScale: CGFloat
    var dark: Bool
    var reduceTransparency: Bool
    var increaseContrast: Bool
    var differentiateWithoutColor: Bool
    var accent: RingColor

    /// Classic sizes at this scale (bubble pieces don't depend on the slot count).
    var metrics: RingMetrics { RingMetrics(theme: .classic, scale: Double(unit), slotCount: 8) }

    var environment: RingEnvironment {
        RingEnvironment(colorScheme: dark ? .dark : .light, reduceTransparency: reduceTransparency, increaseContrast: increaseContrast,
                        differentiateWithoutColor: differentiateWithoutColor, motion: RingMotion(speed: 0, reduceMotion: false))
    }

    /// `side` rounded up to an even number of device pixels, so an image of that size centred on
    /// a pixel-aligned point is itself pixel-aligned.
    func pixelAligned(_ side: CGFloat) -> CGFloat {
        (side * pixelScale / 2).rounded(.up) * 2 / pixelScale
    }

    /// `point` snapped to the device-pixel grid.
    func snapped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x * pixelScale).rounded() / pixelScale, y: (point.y * pixelScale).rounded() / pixelScale)
    }
}

/// The pre-rendered pieces of one Classic bubble face, each the size of `size` and centred on
/// the bubble (nil where the face has nothing to draw).
struct ClassicBubbleArt {
    var size: CGSize
    var disc: CGImage?
    var tile: CGImage?
    var hairline: CGImage?
    var idleInk: CGImage?
    var litInk: CGImage?
    var artwork: CGImage?
    var outline: CGImage?
    var emptyCold: CGImage?
    var emptyHot: CGImage?
    var flash: CGImage?
}

/// A pre-rendered Classic label (tooltip or chip), centred on the label.
struct ClassicLabelArt {
    var size: CGSize
    var image: CGImage?
}

/// The hub's look.
nonisolated struct ClassicHubFace: Hashable {
    var goesBack: Bool
    var armed: Bool
    var holding: Bool
    var badgeBundleID: String?
}

/// Renders the Classic ring's pieces to images for the Core Animation ring, with the same
/// SwiftUI views the configurator's `ClassicRingView` draws (so both look identical), and keeps
/// them: a ring's images are made once, before it is first shown, and reused on every opening.
/// Layers sit on whole device pixels, where SwiftUI would round the same views to.
final class ClassicArtwork {
    static let shared = ClassicArtwork()

    private struct BubbleKey: Hashable {
        var face: SlotFace
        /// Only folders and adjustable slots draw something that faces outward.
        var angle: Double?
        var showsTab: Bool
        var style: ClassicArtStyle
    }

    private enum ImageKey: Hashable {
        case number(Int, angle: Double, style: ClassicArtStyle)
        case hub(ClassicHubFace, style: ClassicArtStyle)
        /// Labels by title, size and where the notch points (quantised to 1/64 pt).
        case label(String, ClassicLabel.Style, width: Int, targetX: Int, targetY: Int, style: ClassicArtStyle)
    }

    private var bubbles: [BubbleKey: ClassicBubbleArt] = [:]
    private var images: [ImageKey: (image: CGImage?, size: CGSize)] = [:]
    private var bytes = 0
    /// Past this many bytes the cache starts over (layers keep the images they show).
    private static let budget = 96 << 20

    private init() {}

    // MARK: Bubbles

    /// Side of the square every bubble image is drawn in: the bubble, its folder tab and its
    /// shadow.
    func bubbleCanvas(_ style: ClassicArtStyle) -> CGFloat {
        let m = style.metrics
        return style.pixelAligned(m.slotSize + 2 * (BubbleShape.tabProtrusion(bubbleRadius: m.slotSize / 2) + 14 * m.unit))
    }

    /// The pieces of `face` for a bubble at `angle` (its direction from the ring centre).
    func bubble(_ face: SlotFace, angle: Double, showsTab: Bool, style: ClassicArtStyle) -> ClassicBubbleArt {
        let facesOutward = face.kind == .folder || face.kind == .adjustable
        let key = BubbleKey(face: face, angle: facesOutward ? (angle * 1e6).rounded() / 1e6 : nil,
                            showsTab: face.kind == .folder ? showsTab : true, style: style)
        if let hit = bubbles[key] { return hit }
        let art = renderBubble(key)
        store(art.byteCount) { bubbles[key] = art }
        return art
    }

    private func renderBubble(_ key: BubbleKey) -> ClassicBubbleArt {
        let style = key.style
        let m = style.metrics
        let side = bubbleCanvas(style)
        let size = CGSize(width: side, height: side)
        let parts = ClassicBubbleParts(face: key.face, angle: key.angle ?? 0, metrics: m, environment: style.environment, showsTab: key.showsTab)
        func piece(_ view: some View) -> CGImage? {
            LayerRasterizer.image(view.frame(width: m.slotSize, height: m.slotSize), size: size, style: style)
        }
        var art = ClassicBubbleArt(size: size)
        if key.face.isEmpty {
            let accent = style.accent.color
            art.emptyCold = piece(parts.emptyDisc(hot: false, accent: accent))
            art.emptyHot = piece(parts.emptyDisc(hot: true, accent: accent))
            art.flash = piece(parts.rejectFlash)
            return art
        }
        if !key.face.isAppIcon { art.disc = piece(parts.disc) }
        art.tile = piece(parts.tileFill)
        art.hairline = piece(parts.hairline)
        let hasInk = key.face.kind == .folder || key.face.kind == .adjustable || { if case .symbol = key.face.icon { true } else { false } }()
        if hasInk {
            art.idleInk = piece(parts.idleInk)
            art.litInk = piece(parts.litInk)
        }
        if parts.hasArtwork { art.artwork = piece(parts.artwork) }
        if style.environment.outlinesHighlight { art.outline = piece(parts.highlightOutline(style.accent.color)) }
        return art
    }

    /// The slot-number badge of a bubble at `angle`, in the bubble's canvas.
    func number(_ number: Int, angle: Double, style: ClassicArtStyle) -> CGImage? {
        let key = ImageKey.number(number, angle: (angle * 1e6).rounded() / 1e6, style: style)
        return image(for: key) {
            let m = style.metrics
            let side = bubbleCanvas(style)
            let parts = ClassicBubbleParts(face: SlotFace(Slot()), angle: angle, metrics: m, environment: style.environment)
            let view = parts.numberBadge(number).frame(width: m.slotSize, height: m.slotSize)
            return (LayerRasterizer.image(view, size: CGSize(width: side, height: side), style: style), CGSize(width: side, height: side))
        }.image
    }

    // MARK: Hub

    /// The hub (with its app badge) in a square canvas around its centre.
    func hub(_ face: ClassicHubFace, style: ClassicArtStyle) -> (image: CGImage?, size: CGSize) {
        image(for: .hub(face, style: style)) {
            let m = style.metrics
            let side = style.pixelAligned(2 * (m.hubRadius + 12 * m.unit))
            let badge = face.badgeBundleID.map { RingViewModel.AppBadge(bundleID: $0, name: "") }
            let view = ClassicHub(goesBack: face.goesBack, armed: face.armed, holding: face.holding, badge: badge,
                                  metrics: m, environment: style.environment)
            let size = CGSize(width: side, height: side)
            return (LayerRasterizer.image(view, size: size, style: style), size)
        }
    }

    // MARK: Labels

    /// A tooltip or chip for `title` laid out by `placement` (its size and notch), centred.
    func label(_ title: String, style labelStyle: ClassicLabel.Style, placement: RadialLabelPlacement, style: ClassicArtStyle) -> ClassicLabelArt {
        let key = ImageKey.label(title, labelStyle, width: Int((placement.size.width * 64).rounded()),
                                 targetX: Int((placement.target.x * 64).rounded()), targetY: Int((placement.target.y * 64).rounded()), style: style)
        let art = image(for: key) {
            let pad = 12 * style.unit
            let size = CGSize(width: style.pixelAligned(placement.size.width + 2 * pad), height: style.pixelAligned(placement.size.height + 2 * pad))
            var centred = placement
            centred.center = .zero
            let view = ClassicLabel(title: title, style: labelStyle, placement: centred, scale: style.unit, environment: style.environment)
            return (LayerRasterizer.image(view, size: size, style: style), size)
        }
        return ClassicLabelArt(size: art.size, image: art.image)
    }

    // MARK: Cache

    private func image(for key: ImageKey, render: () -> (CGImage?, CGSize)) -> (image: CGImage?, size: CGSize) {
        if let hit = images[key] { return hit }
        let (image, size) = render()
        store(image.map { $0.bytesPerRow * $0.height } ?? 0) { images[key] = (image, size) }
        return (image, size)
    }

    private func store(_ cost: Int, _ insert: () -> Void) {
        if bytes + cost > Self.budget {
            bubbles.removeAll()
            images.removeAll()
            bytes = 0
        }
        insert()
        bytes += cost
    }
}

private extension ClassicBubbleArt {
    var byteCount: Int {
        [disc, tile, hairline, idleInk, litInk, artwork, outline, emptyCold, emptyHot, flash]
            .reduce(0) { $0 + ($1.map { $0.bytesPerRow * $0.height } ?? 0) }
    }
}

/// Draws SwiftUI views into bitmaps for layer contents.
enum LayerRasterizer {
    /// `view` centred in a `size` canvas, at the style's pixel scale and appearance, in 8-bit
    /// sRGB (ImageRenderer's own `cgImage` would turn app icons into too-dark PQ images). Laid
    /// out at that display scale, so SwiftUI rounds positions to device pixels as on screen.
    static func image(_ view: some View, size: CGSize, style: ClassicArtStyle) -> CGImage? {
        let content = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, style.dark ? .dark : .light)
            .environment(\.displayScale, style.pixelScale)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        let scale = style.pixelScale
        var image: CGImage?
        let appearance = NSAppearance(named: style.dark ? .darkAqua : .aqua)
        let draw = {
            renderer.render(rasterizationScale: scale) { _, draw in
                guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
                      let context = CGContext(data: nil, width: Int((size.width * scale).rounded()), height: Int((size.height * scale).rounded()),
                                              bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                context.scaleBy(x: scale, y: scale)
                draw(context)
                image = context.makeImage()
            }
        }
        if let appearance { appearance.performAsCurrentDrawingAppearance(draw) } else { draw() }
        return image
    }
}
