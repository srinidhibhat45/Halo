import AppKit
import HaloCore
import Metal
import QuartzCore
import SwiftUI

/// Debug aid: renders ring states (both themes, highlight, folder, editor mode…) and their
/// animations to PNG files so the design can be reviewed without screen recording. Invoked by
/// `Halo --render-snapshots <dir>`; the app exits afterwards.
///
/// Each ring is composited at 2x over a realistic backdrop (a light document or a dark desktop).
/// - The live Classic ring is the overlay's Core Animation view (`ClassicRingLayerView`), built
///   outside any window and rendered with Core Animation's own renderer (`CARenderer`). Its film
///   strips freeze the ring's clock (`speed = 0`, `timeOffset = t`) after committing the
///   animations, so every frame is the exact render-server frame at time t.
/// - Classic in the editor and previews renders with SwiftUI's `ImageRenderer`.
/// - Liquid Glass draws nothing through `ImageRenderer` (and `cacheDisplay` captures nothing from
///   SwiftUI's layers), so Glass shots host the view in an off-screen borderless window and
///   render its layer tree with `CARenderer`, which does draw glass and its backdrop sampling.
enum SnapshotRenderer {
    static func run(outputDirectory: URL) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            Log.app.error("Snapshots: cannot create \(outputDirectory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        var sheet: [(shot: Shot, image: CGImage)] = []
        for shot in Shot.all {
            guard let image = render(shot) else {
                Log.app.error("Snapshots: \(shot.name, privacy: .public) failed to render")
                continue
            }
            write(image, to: outputDirectory.appendingPathComponent(shot.name + ".png"))
            sheet.append((shot, image))
        }
        if let contact = contactSheet(sheet) {
            write(contact, to: outputDirectory.appendingPathComponent("contact-sheet.png"))
        }
        for shot in Shot.parity {
            guard let image = render(shot) else { continue }
            write(image, to: outputDirectory.appendingPathComponent(shot.name + ".png"))
        }
        let layerStrips = LayerStrip.all
        for strip in layerStrips {
            guard let image = render(strip) else {
                Log.app.error("Snapshots: strip \(strip.name, privacy: .public) failed to render")
                continue
            }
            write(image, to: outputDirectory.appendingPathComponent(strip.name + ".png"))
        }
        let strips = FilmStrip.all
        for strip in strips {
            guard let image = render(strip) else {
                Log.app.error("Snapshots: strip \(strip.name, privacy: .public) failed to render")
                continue
            }
            write(image, to: outputDirectory.appendingPathComponent(strip.name + ".png"))
        }
        writeReadme(to: outputDirectory, shots: sheet.map(\.shot), strips: layerStrips.map { ($0.name, $0.caption) } + strips.map { ($0.name, $0.caption) })
    }

    // MARK: Rendering

    static let scale: CGFloat = 2

    private static func render(_ shot: Shot) -> CGImage? {
        let model = shot.makeModel()
        let side = model.metrics.canvasSide
        if shot.theme == .classic && shot.mode == .live {
            let scene = ClassicLayerScene(shot: shot)
            return LayerSnapshotter(size: scene.size)?.render(scene.root)
        }
        let content = scene(shot, model: model)
        if shot.theme == .glass {
            return renderThroughCoreAnimation(content, size: CGSize(width: side, height: side), dark: shot.dark)
        }
        return renderSDR(content, scale: scale)
    }

    /// `model`'s ring over the shot's backdrop, in the shot's appearance.
    private static func scene(_ shot: Shot, model: RingViewModel, freeze: RingMotionFreeze = RingMotionFreeze()) -> some View {
        let side = model.metrics.canvasSide
        return ZStack {
            BackdropView(kind: shot.dark ? .desktop : .document)
            RingView(model: model)
        }
        .frame(width: side, height: side)
        .environment(\.colorScheme, shot.dark ? .dark : .light)
        .environment(\._accessibilityReduceTransparency, shot.reduceTransparency)
        .environment(\._accessibilityReduceMotion, shot.reduceMotion)
        .environment(\._colorSchemeContrast, shot.increaseContrast ? .increased : .standard)
        .environment(\.appearsActive, true)
        .environment(\.ringMotionFreeze, freeze)
        // Round layout to 2x device pixels, as on a Retina screen (ImageRenderer would use 1x).
        .environment(\.displayScale, scale)
    }

    /// The shot's backdrop as an image `side` points square.
    fileprivate static func backdrop(_ shot: Shot, side: CGFloat) -> CGImage? {
        renderSDR(BackdropView(kind: shot.dark ? .desktop : .document)
            .frame(width: side, height: side)
            .environment(\.colorScheme, shot.dark ? .dark : .light)
            .environment(\.displayScale, scale), scale: scale)
    }

    /// Plays `strip` on the Core Animation ring with its clock frozen: the ring is set up
    /// settled, the clock stops, and in time order each change is applied at its time on the
    /// stopped clock and each frame is rendered at exactly its time (as the screen would see
    /// them: a frame before a change shows the animation the change later replaces).
    private static func render(_ strip: LayerStrip) -> CGImage? {
        let scene = ClassicLayerScene(shot: strip.shot, prepare: strip.prepare)
        guard let snapshotter = LayerSnapshotter(size: scene.size) else { return nil }
        scene.freeze()
        var pending = strip.steps.sorted { $0.at < $1.at }[...]
        var frames: [(label: String, image: CGImage)] = []
        for t in strip.times.sorted() {
            while let step = pending.first, step.at <= t {
                pending.removeFirst()
                scene.seek(step.at)
                step.change(scene.model)
                scene.view.sync()
            }
            scene.seek(t)
            guard let full = snapshotter.render(scene.root) else { return nil }
            let crop = min(strip.crop, scene.size.width) * scale
            let origin = (scene.size.width * scale - crop) / 2
            guard let frame = full.cropping(to: CGRect(x: origin, y: origin, width: crop, height: crop)) else { return nil }
            frames.append(("\(Int((t * 1000).rounded())) ms", frame))
        }
        return row(name: strip.name, caption: strip.caption, frames: frames, side: strip.crop * strip.frameScale, columns: strip.columns)
    }

    /// Renders every frame of `strip` through Core Animation and lays them out in one labelled row.
    private static func render(_ strip: FilmStrip) -> CGImage? {
        var frames: [(label: String, image: CGImage)] = []
        for frame in strip.frames {
            let model = strip.shot.makeModel(animationSpeed: 1)
            let image: CGImage?
            switch frame {
            case .frozen(_, let freeze):
                image = renderFrame(strip, model: model, freeze: freeze, trigger: nil, wait: 0)
            case .live(_, let time):
                strip.prepare(model)
                image = renderFrame(strip, model: model, freeze: RingMotionFreeze(), trigger: { strip.trigger(model) }, wait: time)
            }
            guard let image else { return nil }
            frames.append((frame.label, image))
        }
        return row(name: strip.name, caption: strip.caption, frames: frames, side: strip.crop, columns: frames.count)
    }

    /// Frames laid out left to right (wrapping after `columns`), each `side` points, labelled.
    private static func row(name: String, caption: String, frames: [(label: String, image: CGImage)], side: CGFloat, columns: Int) -> CGImage? {
        let rows = stride(from: 0, to: frames.count, by: max(columns, 1)).map { Array(frames[$0..<min($0 + columns, frames.count)]) }
        let view = VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.system(size: 13, weight: .semibold, design: .monospaced))
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        VStack(spacing: 4) {
                            Image(decorative: rows[r][i].image, scale: scale)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: side, height: side)
                            Text(rows[r][i].label).font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.97))
        .environment(\.colorScheme, .light)
        return renderSDR(view, scale: scale)
    }

    /// One frame of `strip`, cropped to `strip.crop` points around the ring centre.
    private static func renderFrame(_ strip: FilmStrip, model: RingViewModel, freeze: RingMotionFreeze,
                                    trigger: (() -> Void)?, wait: TimeInterval) -> CGImage? {
        let side = model.metrics.canvasSide
        let content = scene(strip.shot, model: model, freeze: freeze)
        guard let full = renderThroughCoreAnimation(content, size: CGSize(width: side, height: side), dark: strip.shot.dark,
                                                    after: trigger, wait: wait) else { return nil }
        let crop = min(strip.crop, side) * scale
        let origin = (side * scale - crop) / 2
        return full.cropping(to: CGRect(x: origin, y: origin, width: crop, height: crop))
    }

    /// Renders with `ImageRenderer` straight into an 8-bit sRGB bitmap. (Its own `cgImage` turns
    /// HDR-capable artwork such as app icons into a PQ image that PNG viewers show too dark.)
    private static func renderSDR(_ view: some View, scale: CGFloat) -> CGImage? {
        var image: CGImage?
        ImageRenderer(content: view).render(rasterizationScale: scale) { size, draw in
            guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.scaleBy(x: scale, y: scale)
            draw(context)
            image = context.makeImage()
        }
        return image
    }

    /// Hosts `view` in an off-screen borderless window so SwiftUI builds its layer tree (glass
    /// included), then renders that tree with `CARenderer`.
    ///
    /// With a `trigger`, it runs once the view has settled and the frame is taken `wait` seconds
    /// later, mid-animation (SwiftUI keeps animating in the off-screen window); timing is
    /// accurate to about a display frame.
    static func renderThroughCoreAnimation(_ view: some View, size: CGSize, dark: Bool,
                                           after trigger: (() -> Void)? = nil, wait: TimeInterval = 0) -> CGImage? {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(x: -40_000, y: -40_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        if let trigger {
            trigger()
            RunLoop.main.run(until: Date().addingTimeInterval(wait))
        }
        guard let layer = host.layer else { return nil }
        return LayerSnapshotter(size: size)?.render(layer)
    }

    static func write(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
        } catch {
            Log.app.error("Snapshots: cannot write \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Contact sheet and README

    private static func contactSheet(_ items: [(shot: Shot, image: CGImage)]) -> CGImage? {
        guard !items.isEmpty else { return nil }
        let columns = 5, thumb: CGFloat = 260
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        let sheet = VStack(alignment: .leading, spacing: 18) {
            Text("Halo ring renderer: review set")
                .font(.system(size: 20, weight: .semibold))
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        let item = rows[r][c]
                        VStack(alignment: .leading, spacing: 5) {
                            Image(decorative: item.image, scale: scale)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: thumb, height: thumb)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(item.shot.name).font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Text(item.shot.caption).font(.system(size: 10)).foregroundStyle(.secondary)
                                .frame(width: thumb, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(Color(white: 0.97))
        .environment(\.colorScheme, .light)
        return renderSDR(sheet, scale: 1.5)
    }

    private static func writeReadme(to directory: URL, shots: [Shot], strips: [(name: String, caption: String)]) {
        var text = """
        Halo ring renderer snapshots
        ============================

        Generated by `Halo --render-snapshots <dir>` (SnapshotRenderer.swift). Each PNG is one ring
        state at 2x, composited over a light "document" backdrop or a dark gradient desktop, using
        the real default config (HaloConfig.default) and RingViewModel. contact-sheet.png shows all
        of them.

        Render paths
        - Classic, live overlay: the overlay's own Core Animation view (ClassicRingLayerView),
          built outside any window over a backdrop image and rendered with CARenderer into a Metal
          texture. Its images are the same SwiftUI parts the configurator draws.
        - Classic, editor and previews: SwiftUI ImageRenderer (vector-exact).
        - Glass: ImageRenderer drops every view that has a glassEffect (and its content), and
          NSView.cacheDisplay(in:to:) captures nothing from SwiftUI's layers. Glass shots are
          therefore hosted in an off-screen borderless NSWindow and its layer tree is rendered with
          CARenderer into a Metal texture, which draws Liquid Glass with real backdrop sampling.

        Film strips (one PNG per animation)
        - strip-classic-*: the Core Animation ring with its clock frozen. The ring is set up
          settled, its clock layer is stopped (speed 0), each change is applied at its time on the
          stopped clock (so its animations start exactly then), and each frame sets timeOffset to
          the frame's time before rendering: exact render-server frames at those times.
        - Frozen strips (Glass) hold the SwiftUI motion at given progress values
          (`RingMotionFreeze`): exact frames of the real animation at that progress.
        - "live" strips (Glass, Classic editor) run the real SwiftUI springs in the off-screen
          window and take each frame the given time after the trigger, accurate to about one
          display frame.

        Limitations
        - Static shots run at animation speed 0, so every state is shown settled.
        - CARenderer runs in-process, not in the window server. Glass refraction, blur and
          edge highlights are close to the real thing but the system's adaptive tint (luminance
          sampling, the user's glass transparency slider, active/inactive window state) may
          differ slightly from an on-screen panel. Known gaps of this path:
          * `.regular.tint(...)` draws no tint (only `.clear.tint` does). The renderer also puts
            a tint layer inside highlighted segments (and a red one in the armed hub), so the
            highlight reads either way; on screen the glass tint adds to it.
          * `.opacity` on a glass view is ignored, so dimmed, inherited and dragged segments
            fade their content and switch to `.clear` glass instead (visible on screen too).
          * A scale transform on a glass view draws its content out of register with the
            glass, so no glass view is ever scaled or faded: appear, dismiss, fan, highlight
            and the execute pulse all change the glass shapes themselves.
        - ImageRenderer's own cgImage turns HDR-capable artwork (app icons) into a PQ image;
          Classic images are drawn through its render callback into 8-bit sRGB instead.
        - Reduce Transparency and Increase Contrast are forced through SwiftUI's environment (and
          the Core Animation ring's pinned appearance), so only Halo's own handling shows.
        - App icons come from this Mac (NSWorkspace), so they depend on installed apps.

        - parity-<name>.png: the same state drawn by SwiftUI (`ClassicRingView`, preview mode) at
          2x layout rounding, as a reference for the Core Animation ring's <name>.png.

        Files

        """
        for shot in shots { text += "- \(shot.name).png: \(shot.caption)\n" }
        text += "\nFilm strips\n\n"
        for strip in strips { text += "- \(strip.name).png: \(strip.caption)\n" }
        do {
            try text.write(to: directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        } catch {
            Log.app.error("Snapshots: cannot write README: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Core Animation rendering

/// Renders layer trees with Core Animation's own renderer (`CARenderer`) into a Metal texture
/// and reads them back as sRGB images: Liquid Glass with its backdrop sampling, and layer
/// animations at whatever moment their clocks show.
final class LayerSnapshotter {
    private let size: CGSize
    private let renderer: CARenderer
    private let texture: MTLTexture
    private let queue: MTLCommandQueue
    private let root = CALayer()
    private let colorSpace: CGColorSpace

    /// A renderer for trees `size` points across, at `SnapshotRenderer.scale`.
    init?(size: CGSize) {
        let scale = SnapshotRenderer.scale
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        self.size = size
        self.texture = texture
        self.queue = queue
        colorSpace = sRGB
        renderer = CARenderer(mtlTexture: texture, options: [kCARendererColorSpace: sRGB, kCARendererMetalCommandQueue: queue])
        root.frame = CGRect(x: 0, y: 0, width: width, height: height)
        renderer.layer = root
        renderer.bounds = root.frame
    }

    /// Renders `layer` (moved into this renderer's tree on first use, scaled to pixels).
    func render(_ layer: CALayer) -> CGImage? {
        if layer.superlayer !== root {
            layer.removeFromSuperlayer()
            layer.anchorPoint = .zero
            layer.position = .zero
            layer.setAffineTransform(CGAffineTransform(scaleX: SnapshotRenderer.scale, y: SnapshotRenderer.scale))
            root.addSublayer(layer)
        }
        CATransaction.flush()
        for _ in 0..<3 {
            renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
            renderer.addUpdate(renderer.bounds)
            renderer.render()
            renderer.endFrame()
        }
        // The renderer encodes onto `queue`; an empty buffer after it completes once it has.
        let fence = queue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()

        let width = texture.width, height = texture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let upsideDown: CGImage? = bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: colorSpace, bitmapInfo: info)?.makeImage()
        }
        // The texture's rows run bottom-up relative to CoreGraphics; flip back.
        guard let upsideDown, let flipped = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                                     bytesPerRow: 0, space: colorSpace, bitmapInfo: info) else { return nil }
        flipped.translateBy(x: 0, y: CGFloat(height))
        flipped.scaleBy(x: 1, y: -1)
        flipped.draw(upsideDown, in: CGRect(x: 0, y: 0, width: width, height: height))
        return flipped.makeImage()
    }
}

/// The overlay's Core Animation Classic ring for a shot, over the shot's backdrop, outside any
/// window. Set up settled (animation speed 0); `freeze` then stops its clock for a strip.
private final class ClassicLayerScene {
    let model: RingViewModel
    let view: ClassicRingLayerView
    /// The backdrop and the ring, `size` points.
    let root = CALayer()
    let size: CGSize
    private var start: Double = 0

    init(shot: Shot, prepare: (RingViewModel) -> Void = { _ in }) {
        model = shot.makeModel()
        prepare(model)
        // The canvas as SwiftUI lays it out; the image is its whole pixels (as ImageRenderer
        // truncates it), the ring's top-left corner on the image's.
        let side = model.metrics.canvasSide
        let pixels = (side * SnapshotRenderer.scale).rounded(.down) / SnapshotRenderer.scale
        size = CGSize(width: pixels, height: pixels)
        view = ClassicRingLayerView(model: model)
        view.pinnedAppearance = ClassicRingLayerView.Appearance(
            dark: shot.dark, reduceTransparency: shot.reduceTransparency, increaseContrast: shot.increaseContrast,
            differentiateWithoutColor: false, reduceMotion: shot.reduceMotion, pixelScale: SnapshotRenderer.scale
        )
        view.frame = CGRect(x: 0, y: 0, width: side, height: side)
        root.frame = CGRect(origin: .zero, size: size)
        let backdrop = CALayer()
        backdrop.frame = root.bounds
        backdrop.contents = SnapshotRenderer.backdrop(shot, side: side)
        backdrop.contentsScale = SnapshotRenderer.scale
        root.addSublayer(backdrop)
        view.sync()
        if let ring = view.layer {
            // The root is y-up.
            ring.frame = CGRect(x: 0, y: pixels - side, width: side, height: side)
            root.addSublayer(ring)
        }
    }

    /// Stops the ring's clock now; later times count from here. Animations run at speed 1 from
    /// here on.
    func freeze() {
        let clock = view.clock
        start = clock.convertTime(CACurrentMediaTime(), from: nil)
        clock.speed = 0
        clock.timeOffset = start
        model.animationSpeed = 1
    }

    /// Moves the stopped clock to `t` seconds after `freeze`.
    func seek(_ t: Double) {
        view.clock.timeOffset = start + t
    }
}

// MARK: - Shots

/// One reviewed ring state.
private extension SnapshotRenderer {
    /// The default ring with only the slots at `keep` filled.
    static func sparse(_ keep: Set<Int>) -> Ring {
        var ring = DefaultRings.global()
        for i in ring.slots.indices where !keep.contains(i) { ring.clear(i) }
        return ring
    }
}

private struct Shot {
    var name: String
    var caption: String
    var theme: RingTheme
    var dark = false
    var mode: RingViewModel.Mode = .live
    var ring: Ring?
    var reduceTransparency = false
    var reduceMotion = false
    var increaseContrast = false
    var settings: (inout AppSettings) -> Void = { _ in }
    var configure: (RingViewModel) -> Void = { _ in }

    /// A model like the overlay's: presented, trigger held (so the hub isn't armed), settled
    /// (animation speed 0) unless `animationSpeed` says otherwise.
    func makeModel(animationSpeed: Double = 0) -> RingViewModel {
        let config = HaloConfig.default
        var s = config.settings
        s.theme = theme
        settings(&s)
        s.animationSpeed = animationSpeed
        let model = RingViewModel(mode: mode, ring: ring ?? config.globalRing, settings: s)
        model.isPresented = true
        model.isHolding = true
        configure(model)
        return model
    }

    /// The live Classic shots drawn by SwiftUI in preview mode (same pieces, no live-only
    /// states), as references for the Core Animation ring: `parity-<name>.png` should match
    /// `<name>.png` pixel for pixel, give or take antialiasing.
    static var parity: [Shot] {
        all.filter { $0.theme == .classic && $0.mode == .live && !$0.name.contains("folder") && !$0.name.contains("armed") }
            .map { shot in
                var reference = shot
                reference.name = "parity-" + shot.name
                reference.caption = "SwiftUI reference for \(shot.name)."
                reference.mode = .preview
                return reference
            }
    }

    static var all: [Shot] {
        let global = HaloConfig.default.globalRing
        let ai = global.ring(at: [3]) ?? DefaultRings.ai()
        let windows = global.ring(at: [5]) ?? DefaultRings.windows()
        var withGaps = global
        withGaps.clear(4)
        withGaps.clear(7)
        withGaps[1].tint = .preset(.orange)
        let twelve = Ring(slots: global.slots + [
            Slot(action: .edit(.copy)), Slot(action: .edit(.paste)), Slot(action: .media(.volumeUp)), Slot(),
        ])
        let four = Ring(slots: Array(global.slots.prefix(4)))
        func fan(_ child: Ring, from slot: Int, title: String, highlight: Int?) -> (RingViewModel) -> Void {
            { model in
                model.showLevel(child, transition: .push(fromSlot: slot))
                model.breadcrumb = [title]
                model.highlighted = highlight
            }
        }

        return [
            Shot(name: "classic-idle", caption: "Classic, just opened (trigger held), light document.", theme: .classic),
            Shot(name: "classic-idle-dark", caption: "Classic on a dark desktop, dark mode.", theme: .classic, dark: true),
            Shot(name: "classic-highlight", caption: "Slot 2 (Play/Pause) highlighted: black tile, white glyph, tooltip outward.",
                 theme: .classic, configure: { $0.highlighted = 2 }),
            Shot(name: "classic-highlight-app-dark", caption: "Finder (app icon) highlighted on dark: dark disc behind the icon.",
                 theme: .classic, dark: true, configure: { $0.highlighted = 6 }),
            Shot(name: "classic-hub-armed", caption: "Tap mode, pointer over the hub: pale red hub with red ×.",
                 theme: .classic, configure: { $0.isHolding = false; $0.isHubHovered = true }),
            Shot(name: "classic-folder-ai", caption: "AI folder open: children fanned on the outer circle, root dimmed; child 1 highlighted.",
                 theme: .classic, configure: fan(ai, from: 3, title: "AI", highlight: 1)),
            Shot(name: "classic-folder-windows-dark", caption: "Windows folder open (bottom-left), child 2 highlighted, dark.",
                 theme: .classic, dark: true, configure: fan(windows, from: 5, title: "Windows", highlight: 2)),
            Shot(name: "classic-labels-always", caption: "labelMode .always: a caption chip outward of every bubble.",
                 theme: .classic, settings: { $0.labelMode = .always }, configure: { $0.highlighted = 0 }),
            Shot(name: "classic-numbers", caption: "Slot numbers on the inner edge of each bubble.",
                 theme: .classic, settings: { $0.showSlotNumbers = true }),
            Shot(name: "classic-editor", caption: "Editor: slot 1 selected (orange tint), drop target on empty slot 4, hover on 6, empty 7.",
                 theme: .classic, mode: .editor, ring: withGaps,
                 configure: { $0.selected = 1; $0.dropTarget = 4; $0.highlighted = 6 }),
            Shot(name: "classic-editor-app-ring", caption: "Editor, app ring: slots 4, 6, 7 inherited (ghosted, dashed), slot 2 being dragged onto 5.",
                 theme: .classic, mode: .editor,
                 configure: {
                     $0.appBadge = .init(bundleID: "com.apple.Safari", name: "Safari")
                     $0.inheritedSlots = [4, 6, 7]
                     $0.dragSource = 2
                     $0.dropTarget = 5
                 }),
            Shot(name: "classic-editor-folder", caption: "Editor inside the Windows folder (one level at a time, six slots), slot 1 selected.",
                 theme: .classic, mode: .editor,
                 configure: { model in
                     model.showLevel(windows, transition: .push(fromSlot: 5))
                     model.breadcrumb = ["Windows"]
                     model.selected = 1
                 }),
            Shot(name: "classic-preview", caption: "Preview mode (theme card / onboarding) with a highlight and tooltip.",
                 theme: .classic, mode: .preview, configure: { $0.highlighted = 4 }),
            Shot(name: "classic-4-slots", caption: "Four slots.", theme: .classic, ring: four, configure: { $0.highlighted = 1 }),
            Shot(name: "classic-3-actions-closed-up", caption: "Eight slots, three actions, gaps closed (the live ring).",
                 theme: .classic, ring: SnapshotRenderer.sparse([0, 3, 5]).compacted().ring, configure: { $0.highlighted = 1 }),
            Shot(name: "glass-5-actions-closed-up", caption: "Eight slots, five actions, gaps closed (the live ring).",
                 theme: .glass, ring: SnapshotRenderer.sparse([0, 2, 3, 5, 6]).compacted().ring, configure: { $0.highlighted = 0 }),
            Shot(name: "classic-12-slots", caption: "Twelve slots (radius grows), volume dot on slot 10, one empty.",
                 theme: .classic, ring: twelve, configure: { $0.highlighted = 10 }),
            Shot(name: "classic-scale-0.8", caption: "Ring size 0.8.", theme: .classic,
                 settings: { $0.ringScale = 0.8 }, configure: { $0.highlighted = 1 }),
            Shot(name: "classic-scale-1.4", caption: "Ring size 1.4.", theme: .classic,
                 settings: { $0.ringScale = 1.4 }, configure: { $0.highlighted = 5 }),
            Shot(name: "classic-contrast", caption: "Increase Contrast + Reduce Transparency: solid fills, outlines, accent ring on highlight.",
                 theme: .classic, reduceTransparency: true, increaseContrast: true, configure: { $0.highlighted = 3 }),
            Shot(name: "classic-app-ring", caption: "App ring: app badge on the hub; tap mode with Lock highlighted.",
                 theme: .classic, configure: {
                     $0.appBadge = .init(bundleID: "com.apple.Safari", name: "Safari")
                     $0.highlighted = 7
                 }),
            Shot(name: "glass-idle", caption: "Glass, just opened, light document.", theme: .glass),
            Shot(name: "glass-idle-dark", caption: "Glass on a dark desktop, dark mode.", theme: .glass, dark: true),
            Shot(name: "glass-highlight", caption: "Glass, slot 2 highlighted: accent-tinted segment, white glyph, title in the hub.",
                 theme: .glass, configure: { $0.highlighted = 2 }),
            Shot(name: "glass-highlight-dark", caption: "Glass highlight on dark.", theme: .glass, dark: true, configure: { $0.highlighted = 6 }),
            Shot(name: "glass-folder-ai", caption: "Glass AI folder: outer partial band, root dimmed, back hub.",
                 theme: .glass, configure: fan(ai, from: 3, title: "AI", highlight: 2)),
            Shot(name: "glass-folder-windows-dark", caption: "Glass Windows folder on dark, nothing highlighted (hub: back + name).",
                 theme: .glass, dark: true, configure: fan(windows, from: 5, title: "Windows", highlight: nil)),
            Shot(name: "glass-labels-always", caption: "Glass with captions and numbers.", theme: .glass,
                 settings: { $0.labelMode = .always; $0.showSlotNumbers = true }, configure: { $0.highlighted = 4 }),
            Shot(name: "glass-editor", caption: "Glass editor: selection, drop target, hover, empty slots.",
                 theme: .glass, mode: .editor, ring: withGaps,
                 configure: { $0.selected = 1; $0.dropTarget = 4; $0.highlighted = 6 }),
            Shot(name: "glass-editor-app-ring", caption: "Glass editor, app ring: inherited slots ghosted, slot 2 dragged onto 5.",
                 theme: .glass, dark: true, mode: .editor,
                 configure: {
                     $0.appBadge = .init(bundleID: "com.apple.Safari", name: "Safari")
                     $0.inheritedSlots = [4, 6, 7]
                     $0.dragSource = 2
                     $0.dropTarget = 5
                 }),
            Shot(name: "glass-preview", caption: "Glass preview mode with a highlight (hub shows the title).",
                 theme: .glass, mode: .preview, configure: { $0.highlighted = 0 }),
            Shot(name: "glass-hub-armed-dark", caption: "Glass tap mode, pointer over the hub (red-tinted close).",
                 theme: .glass, dark: true, configure: { $0.isHolding = false; $0.isHubHovered = true }),
            Shot(name: "glass-reduce-transparency", caption: "Glass with Reduce Transparency: solid fills and hairlines.",
                 theme: .glass, reduceTransparency: true, configure: { $0.highlighted = 2 }),
            Shot(name: "glass-reduce-transparency-dark", caption: "Glass with Reduce Transparency, dark.",
                 theme: .glass, dark: true, reduceTransparency: true, configure: { $0.highlighted = 0 }),
        ]
    }
}

// MARK: - Film strips

/// Model changes shared by the film strips.
private enum StripChanges {
    static let global = HaloConfig.default.globalRing
    static let ai = global.ring(at: [3]) ?? DefaultRings.ai()
    static let windows = global.ring(at: [5]) ?? DefaultRings.windows()

    static func openAI(_ model: RingViewModel) {
        model.showLevel(ai, transition: .push(fromSlot: 3))
        model.breadcrumb = ["AI"]
    }

    static func closeFolder(_ model: RingViewModel) {
        model.showLevel(global, transition: .pop(toSlot: 3))
        model.breadcrumb = []
    }

    /// Hovering another root slot while a folder is open: back out, then into that folder.
    static func switchToWindows(_ model: RingViewModel) {
        model.showLevel(global, transition: .pop(toSlot: 3))
        model.showLevel(windows, transition: .push(fromSlot: 5))
        model.breadcrumb = ["Windows"]
    }

    static func collapsed(_ model: RingViewModel) { model.isPresented = false }
    static func present(_ model: RingViewModel) { model.isPresented = true }
    static func highlight(_ index: Int?) -> (RingViewModel) -> Void { { $0.highlighted = index } }
}

/// One animation of the Core Animation Classic ring, frame by frame on its frozen clock.
private struct LayerStrip {
    var name: String
    var caption: String
    var shot: Shot
    /// Changes to the model at these times (seconds after the strip starts).
    var steps: [(at: Double, change: (RingViewModel) -> Void)]
    /// Frame times (seconds).
    var times: [Double]
    /// Side of the square around the ring centre that each frame shows (points).
    var crop: CGFloat = 300
    /// Puts the model in its starting state (shown settled) before the clock stops.
    var prepare: (RingViewModel) -> Void = { _ in }
    var columns = 9
    /// Frames are drawn at this fraction of their size in the strip.
    var frameScale: CGFloat = 1

    static let bloom: [Double] = [0, 0.03, 0.06, 0.09, 0.12, 0.16, 0.22, 0.3, 0.45]
    /// Every 60 Hz frame of the first half second.
    static let bloom60: [Double] = (0...30).map { Double($0) / 60 }

    static var all: [LayerStrip] {
        typealias C = StripChanges
        let classic = Shot(name: "classic", caption: "", theme: .classic)
        let highlighted = Shot(name: "classic", caption: "", theme: .classic, configure: C.highlight(2))
        let twelve = Ring(slots: C.global.slots + [
            Slot(action: .edit(.copy)), Slot(action: .edit(.paste)), Slot(action: .media(.volumeUp)), Slot(action: .edit(.undo)),
        ])
        let three = SnapshotRenderer.sparse([0, 3, 5]).compacted().ring
        let one = SnapshotRenderer.sparse([0]).compacted().ring
        var withGap = C.global
        withGap.clear(4)
        func reject(_ model: RingViewModel) { model.reject(4) }
        func execute(_ model: RingViewModel) { model.executing = 2 }
        let flash = RingMotion.flashDuration(speed: 1, reduceMotion: false)
        return [
            LayerStrip(name: "strip-classic-appear", caption: "Appear: the hub, then bubbles one after another clockwise from 12 o'clock, each out of the centre along its spoke (ms after isPresented = true).",
                       shot: classic, steps: [(0, C.present)], times: bloom + [1.5], crop: 300, prepare: C.collapsed, columns: 10),
            LayerStrip(name: "strip-classic-appear-60hz", caption: "Appear, every 60 Hz frame for 0.5 s.",
                       shot: classic, steps: [(0, C.present)], times: bloom60, crop: 300, prepare: C.collapsed, columns: 8, frameScale: 0.6),
            LayerStrip(name: "strip-classic-appear-dark", caption: "Appear on the dark desktop, dark mode.",
                       shot: Shot(name: "classic", caption: "", theme: .classic, dark: true), steps: [(0, C.present)], times: bloom,
                       crop: 300, prepare: C.collapsed),
            LayerStrip(name: "strip-classic-appear-12", caption: "Appear with twelve slots (larger radius, the cascade spread over the same 0.24 s).",
                       shot: Shot(name: "classic", caption: "", theme: .classic, ring: twelve), steps: [(0, C.present)], times: bloom,
                       crop: 400, prepare: C.collapsed),
            LayerStrip(name: "strip-classic-appear-3", caption: "Appear, closed-up ring of three slots.",
                       shot: Shot(name: "classic", caption: "", theme: .classic, ring: three), steps: [(0, C.present)], times: bloom,
                       crop: 300, prepare: C.collapsed),
            LayerStrip(name: "strip-classic-appear-1", caption: "Appear, a single slot.",
                       shot: Shot(name: "classic", caption: "", theme: .classic, ring: one), steps: [(0, C.present)], times: bloom,
                       crop: 300, prepare: C.collapsed),
            LayerStrip(name: "strip-classic-dismiss", caption: "Dismiss (cancel) with slot 2 highlighted: everything contracts to the centre together; gone by RingMotion.dismissDuration (160 ms).",
                       shot: highlighted, steps: [(0, C.collapsed)], times: [0, 0.02, 0.04, 0.06, 0.08, 0.1, 0.12, 0.14, 0.16]),
            LayerStrip(name: "strip-classic-execute", caption: "Slot 2 chosen: it pulses (1 → 1.1 → 1) while the rest contracts, then the ring dismisses at 80 ms.",
                       shot: highlighted, steps: [(0, execute), (flash, C.collapsed)], times: [0, 0.03, 0.06, 0.09, 0.12, 0.15, 0.18, 0.22, 0.26]),
            LayerStrip(name: "strip-classic-reopen", caption: "Dismissed, then reopened 60 ms in: each bubble turns back from where it is (nearly-shown ones at once, collapsed ones in the cascade).",
                       shot: classic, steps: [(0, C.collapsed), (0.06, C.present)], times: [0, 0.03, 0.06, 0.09, 0.12, 0.16, 0.22, 0.3, 0.45]),
            LayerStrip(name: "strip-classic-highlight", caption: "Highlight sweeping 2 → 3 → 4 every 40 ms: fill and glyph colour 120 ms ease-out, tooltip slides out 4 pt.",
                       shot: classic, steps: [(0, C.highlight(2)), (0.04, C.highlight(3)), (0.08, C.highlight(4))],
                       times: [0, 0.02, 0.04, 0.06, 0.08, 0.1, 0.12, 0.16, 0.22]),
            LayerStrip(name: "strip-classic-fan", caption: "AI folder opening: children travel out of the folder along the arc, centre child first (25 ms steps); root dims.",
                       shot: classic, steps: [(0, C.openAI)], times: [0, 0.025, 0.05, 0.075, 0.1, 0.14, 0.18, 0.25, 0.4], crop: 440),
            LayerStrip(name: "strip-classic-fan-in", caption: "AI folder closing: children fold back into the folder, the root brightens.",
                       shot: classic, steps: [(0, C.closeFolder)], times: [0, 0.03, 0.06, 0.09, 0.12, 0.16, 0.22], crop: 440,
                       prepare: C.openAI),
            LayerStrip(name: "strip-classic-switch", caption: "AI open, then the Windows folder (hovering its root slot): AI folds while Windows unfolds.",
                       shot: classic, steps: [(0, C.switchToWindows)], times: [0, 0.03, 0.06, 0.09, 0.12, 0.16, 0.22, 0.3, 0.45], crop: 440,
                       prepare: C.openAI),
            LayerStrip(name: "strip-classic-switch-back", caption: "AI opening, and 60 ms in the Windows folder instead: AI turns back mid-fan.",
                       shot: classic, steps: [(0, C.openAI), (0.06, C.switchToWindows)], times: [0, 0.03, 0.06, 0.09, 0.12, 0.16, 0.22, 0.3, 0.45],
                       crop: 440),
            LayerStrip(name: "strip-classic-reject", caption: "Empty slot 4 rejected: red flash and a 6 pt shake (3 oscillations, 0.3 s).",
                       shot: Shot(name: "classic", caption: "", theme: .classic, ring: withGap), steps: [(0, reject)],
                       times: [0, 0.025, 0.05, 0.075, 0.1, 0.15, 0.2, 0.3, 0.45]),
            LayerStrip(name: "strip-classic-reduce-motion", caption: "Reduce Motion: the ring cross-fades in place (0.15 s), nothing moves or scales.",
                       shot: Shot(name: "classic", caption: "", theme: .classic, reduceMotion: true), steps: [(0, C.present)],
                       times: [0, 0.03, 0.06, 0.09, 0.12, 0.2], crop: 300, prepare: C.collapsed),
        ]
    }
}

/// One SwiftUI animation (Glass, Classic editor), frame by frame, as a row of frames of `shot`.
private struct FilmStrip {
    enum Frame {
        /// Motion held at these progress values.
        case frozen(String, RingMotionFreeze)
        /// The real animation, this many seconds after `trigger`.
        case live(String, TimeInterval)

        var label: String {
            switch self {
            case .frozen(let label, _), .live(let label, _): label
            }
        }
    }

    var name: String
    var caption: String
    var shot: Shot
    var frames: [Frame]
    /// Side of the square around the ring centre that each frame shows (points).
    var crop: CGFloat
    /// Live frames: puts the model in its starting state before the view is built.
    var prepare: (RingViewModel) -> Void = { _ in }
    /// Live frames: starts the animation once the view has settled.
    var trigger: (RingViewModel) -> Void = { _ in }

    static let progress: [Double] = [0, 0.1, 0.25, 0.5, 0.75, 1]
    static let times: [TimeInterval] = [0, 0.017, 0.033, 0.05, 0.083, 0.133, 0.2, 0.3]

    static func fan(_ p: Double) -> Frame { .frozen("p \(p)", RingMotionFreeze(fan: p)) }
    static func highlight(_ p: Double) -> Frame { .frozen("h \(p)", RingMotionFreeze(highlight: p)) }
    static func live(_ t: TimeInterval) -> Frame { .live("\(Int((t * 1000).rounded())) ms", t) }

    static var all: [FilmStrip] {
        typealias C = StripChanges
        /// The overlay's execute: the slot pulses, then the ring dismisses after the flash.
        func execute(_ model: RingViewModel) {
            model.executing = 2
            let flash = RingMotion.flashDuration(speed: 1, reduceMotion: false)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(flash))
                model.isPresented = false
            }
        }
        /// Dismissed, then reopened 60 ms in.
        func reopen(_ model: RingViewModel) {
            model.isPresented = false
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.06))
                model.isPresented = true
            }
        }
        /// The editor entering a folder: the new level builds clockwise from 12 o'clock.
        func enterWindowsInEditor(_ model: RingViewModel) {
            model.showLevel(C.windows, transition: .push(fromSlot: 5))
            model.breadcrumb = ["Windows"]
        }
        let glass = Shot(name: "glass", caption: "", theme: .glass)
        let highlighted = Shot(name: "glass", caption: "", theme: .glass, configure: C.highlight(2))
        let bloom: [TimeInterval] = [0, 0.03, 0.06, 0.09, 0.12, 0.16, 0.22, 0.3, 0.45]
        let interruption: [TimeInterval] = [0, 0.03, 0.06, 0.09, 0.12, 0.16, 0.22, 0.3]
        let build: [TimeInterval] = [0, 0.06, 0.12, 0.18, 0.24, 0.32, 0.5]
        return [
            FilmStrip(name: "strip-glass-appear-live", caption: "Glass appear: the hub, then segments one after another clockwise, each growing out of the hub (real springs, ms after isPresented = true).",
                      shot: glass, frames: bloom.map(live), crop: 360, prepare: C.collapsed, trigger: C.present),
            FilmStrip(name: "strip-glass-appear-dark-live", caption: "Glass appear on the dark desktop.",
                      shot: Shot(name: "glass", caption: "", theme: .glass, dark: true), frames: bloom.map(live), crop: 360,
                      prepare: C.collapsed, trigger: C.present),
            FilmStrip(name: "strip-glass-dismiss-live", caption: "Glass dismiss (cancel), real spring; gone by RingMotion.dismissDuration (160 ms).",
                      shot: highlighted, frames: [0, 0.02, 0.04, 0.06, 0.08, 0.1, 0.12, 0.14, 0.16].map(live), crop: 360, trigger: C.collapsed),
            FilmStrip(name: "strip-glass-execute-live", caption: "Glass: slot 2 chosen: it pulses while the rest folds, then the ring dismisses (real springs).",
                      shot: highlighted, frames: [0, 0.03, 0.06, 0.09, 0.12, 0.16, 0.2, 0.26].map(live), crop: 360, trigger: execute),
            FilmStrip(name: "strip-glass-fan", caption: "Glass AI folder fanning out at progress 0 … 1 (frozen).",
                      shot: Shot(name: "glass", caption: "", theme: .glass, configure: C.openAI), frames: progress.map(fan), crop: 500),
            FilmStrip(name: "strip-glass-fan-live", caption: "Glass AI folder opening, real springs, ms after the level change.",
                      shot: glass, frames: times.map(live), crop: 500, trigger: C.openAI),
            FilmStrip(name: "strip-glass-highlight", caption: "Glass slot 2 highlight at strength 0 … 1 (frozen; 0.5 is mid-animation).",
                      shot: highlighted, frames: [0, 0.25, 0.5, 0.75, 1].map(highlight), crop: 360),
            FilmStrip(name: "strip-glass-reopen-live", caption: "Glass dismissed, then reopened 60 ms in: every segment reverses from where it is.",
                      shot: glass, frames: interruption.map(live), crop: 360, trigger: reopen),
            FilmStrip(name: "strip-glass-switch-live", caption: "Glass: AI open, then the Windows folder (hovering its root slot): AI folds while Windows unfolds.",
                      shot: Shot(name: "glass", caption: "", theme: .glass, configure: C.openAI), frames: interruption.map(live), crop: 500,
                      trigger: C.switchToWindows),
            FilmStrip(name: "strip-glass-reduce-motion-live", caption: "Reduce Motion: the glass ring cross-fades in place (0.15 s), no growth.",
                      shot: Shot(name: "glass", caption: "", theme: .glass, reduceMotion: true), frames: [0, 0.03, 0.06, 0.09, 0.12, 0.2].map(live),
                      crop: 360, prepare: C.collapsed, trigger: C.present),
            FilmStrip(name: "strip-glass-editor-build-live", caption: "Glass editor entering the Windows folder: hub, then segments clockwise, each growing out of the hub.",
                      shot: Shot(name: "glass", caption: "", theme: .glass, mode: .editor), frames: build.map(live), crop: 360,
                      trigger: enterWindowsInEditor),
            FilmStrip(name: "strip-classic-editor-build-live", caption: "Classic editor (SwiftUI) entering the Windows folder: bubbles slide out of the hub clockwise.",
                      shot: Shot(name: "classic", caption: "", theme: .classic, mode: .editor), frames: build.map(live), crop: 300,
                      trigger: enterWindowsInEditor),
        ]
    }
}

// MARK: - Backdrops

/// What the ring is composited over: a busy light document window, or a dark desktop.
private struct BackdropView: View {
    enum Kind {
        case document
        case desktop
    }

    let kind: Kind

    var body: some View {
        switch kind {
        case .document: document
        case .desktop: desktop
        }
    }

    /// A white page of grey text lines with a heading, a photo block and a sidebar.
    private var document: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .topLeading) {
                Color(white: 0.92)
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(0..<16, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(white: i % 5 == 0 ? 0.62 : 0.8))
                                .frame(width: w * 0.14 * CGFloat(0.6 + Double((i * 7) % 5) / 10), height: 7)
                        }
                    }
                    .padding(16)
                    .frame(width: w * 0.22, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.22)).frame(width: w * 0.42, height: 16)
                        ForEach(0..<7, id: \.self) { i in
                            textLine(i, width: w * 0.66)
                        }
                        HStack(spacing: 12) {
                            LinearGradient(colors: [Color(red: 0.42, green: 0.68, blue: 0.95), Color(red: 0.98, green: 0.78, blue: 0.45)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(width: w * 0.3, height: w * 0.2)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(0..<6, id: \.self) { i in textLine(i + 3, width: w * 0.32) }
                            }
                        }
                        ForEach(7..<24, id: \.self) { i in
                            textLine(i, width: w * 0.66)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color.white)
                }
            }
        }
    }

    private func textLine(_ i: Int, width: CGFloat) -> some View {
        let fraction = [0.98, 0.93, 1.0, 0.86, 0.95, 0.72, 0.99, 0.9, 0.6][i % 9]
        return RoundedRectangle(cornerRadius: 2.5)
            .fill(Color(white: 0.72))
            .frame(width: width * fraction, height: 6)
    }

    /// A deep blue-violet gradient with soft light blooms, like a macOS wallpaper.
    private var desktop: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.2), Color(red: 0.2, green: 0.1, blue: 0.36), Color(red: 0.06, green: 0.18, blue: 0.32)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color(red: 0.95, green: 0.45, blue: 0.55).opacity(0.55))
                    .frame(width: w * 0.55).blur(radius: w * 0.12).offset(x: w * 0.3, y: -h * 0.28)
                Circle().fill(Color(red: 0.3, green: 0.6, blue: 1).opacity(0.5))
                    .frame(width: w * 0.6).blur(radius: w * 0.13).offset(x: -w * 0.32, y: h * 0.3)
                Ellipse().fill(Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.45))
                    .frame(width: w * 0.7, height: w * 0.3).blur(radius: w * 0.08).offset(x: w * 0.05, y: h * 0.05)
            }
        }
    }
}
