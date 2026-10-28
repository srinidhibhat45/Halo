import AppKit
import HaloCore
import SwiftUI

/// What a slot shows, resolved from its `Slot` (title, icon and the small affordances).
struct SlotFace: Hashable {
    enum Kind: Hashable {
        case empty
        case action
        /// Opens a nested ring: Classic draws a tab, Glass an outer arc.
        case folder
        /// Volume/brightness: adjustable with the scroll wheel, marked with a dot.
        case adjustable
    }

    var title: String
    var icon: IconSpec?
    var kind: Kind
    var tint: RingColor?

    init(_ slot: Slot) {
        title = slot.displayTitle
        icon = slot.displayIcon
        tint = slot.tint
        switch slot.action {
        case nil: kind = .empty
        case .folder: kind = .folder
        case .media(let command):
            switch command {
            case .volumeUp, .volumeDown, .brightnessUp, .brightnessDown: kind = .adjustable
            default: kind = .action
            }
        default: kind = .action
        }
    }

    var isEmpty: Bool { kind == .empty }

    var isAppIcon: Bool {
        if case .app = icon { true } else { false }
    }
}

/// How one slot is drawn right now; derived from `RingViewModel` once per update so slot views
/// only re-render when their own state changes.
struct SlotDrawState: Equatable {
    /// 0 idle, 0.6 editor hover, 1 highlighted (or an open folder).
    var highlight: Double = 0
    var isSelected = false
    var isDropTarget = false
    var isExecuting = false
    /// A folder whose children are fanned out around it.
    var isOpenFolder = false
    /// A root slot behind a fanned-out folder.
    var isDimmed = false
    /// Changes every time this slot is rejected (0 = never).
    var rejectToken = 0
    /// Editor: the slot being dragged to another position (drawn lifted).
    var isDragSource = false
    /// Editor: an app ring's slot showing the Everywhere ring's action (drawn ghosted).
    var isInherited = false

    /// Opacity of the whole slot: dimmed behind a fan, ghosted when inherited, faded while
    /// being dragged.
    var opacity: Double {
        if isDimmed { return 0.55 }
        if isDragSource { return 0.7 }
        return isInherited ? 0.45 : 1
    }
}

extension RingViewModel {
    /// The number badge of slot `index` of the shown level: the digit key that runs it (1–9,
    /// then 0 for the tenth), or nil when numbers are off or beyond ten.
    func slotNumber(_ index: Int) -> Int? {
        guard showNumbers else { return nil }
        return index < 9 ? index + 1 : (index == 9 ? 0 : nil)
    }

    /// Draw state of slot `index` of the shown level.
    func drawState(ofSlot index: Int) -> SlotDrawState {
        var state = SlotDrawState()
        if highlighted == index { state.highlight = mode == .editor ? 0.6 : 1 }
        if executing == index { state.highlight = 1 }
        if mode == .editor {
            state.isSelected = selected == index
            state.isDropTarget = dropTarget == index
            state.isDragSource = dragSource == index
            state.isInherited = inheritedSlots.contains(index)
        }
        state.isExecuting = executing == index
        if rejected == index { state.rejectToken = rejectCount }
        return state
    }

    /// Draw state of slot `index` of the root ring while a folder is fanned out over it.
    func drawState(ofRootSlot index: Int) -> SlotDrawState {
        var state = SlotDrawState()
        if folderAnchor == index {
            state.highlight = 1
            state.isOpenFolder = true
        } else {
            state.isDimmed = true
        }
        return state
    }

    /// The ring drawn as the main circle: the root while a folder is fanned out, else the level.
    var baseRing: Ring { isFanned ? (rootRing ?? ring) : ring }

    /// Whether the hub means "back" rather than "close".
    var hubGoesBack: Bool { folderAnchor != nil || !breadcrumb.isEmpty }

    /// The pointer is over the hub in tap mode: nothing is highlighted while the ring is open and
    /// the trigger is released, so a click would close (or go back). Derived; see the renderer's
    /// contract request for an explicit flag.
    var isHubArmed: Bool {
        mode == .live && isPresented && isHubHovered && executing == nil
    }
}

extension RingMetrics {
    /// The ring's size multiplier (Medium = 1), for drawing details `RingMetrics` doesn't list.
    var unit: CGFloat { scale }
}

/// Resolved environment shared by both themes: colour scheme, accessibility and motion.
struct RingEnvironment: Equatable {
    var colorScheme: ColorScheme
    var reduceTransparency: Bool
    var increaseContrast: Bool
    var differentiateWithoutColor: Bool
    var motion: RingMotion

    /// Highlights need a non-colour cue (an outline).
    var outlinesHighlight: Bool { increaseContrast || differentiateWithoutColor }
}

// MARK: - Icons

/// Draws a slot's icon for the ring: SF Symbols in one colour at a fixed point size, app icons
/// larger (they carry their own padding), emoji, and custom images clipped to a circle.
struct RingIcon: View {
    let spec: IconSpec?
    /// Point size of SF Symbols (the glyph box is about this size).
    var symbolSize: CGFloat
    var appIconSize: CGFloat
    var color: Color
    var renderingMode: SymbolRenderingMode = .monochrome
    var weight: Font.Weight = .medium

    var body: some View {
        content.accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch spec {
        case .symbol(let name):
            Image(systemName: SymbolNames.resolved(name))
                .font(.system(size: symbolSize, weight: weight))
                .symbolRenderingMode(renderingMode)
                .foregroundStyle(color)
        case .app(let bundleID):
            Image(nsImage: AppCatalog.shared.icon(forBundleID: bundleID))
                .resizable()
                .interpolation(.high)
                .frame(width: appIconSize, height: appIconSize)
        case .image(let png):
            if let image = DecodedImageCache.shared.image(for: png) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: appIconSize * 0.92, height: appIconSize * 0.92)
                    .clipShape(Circle())
            } else {
                Image(systemName: "photo")
                    .font(.system(size: symbolSize, weight: weight))
                    .foregroundStyle(color)
            }
        case .emoji(let text):
            Text(text)
                .font(.system(size: symbolSize * 1.12))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(width: appIconSize, height: appIconSize)
        case nil:
            EmptyView()
        }
    }
}

/// Validates SF Symbol names once each, so a mistyped or unavailable name still draws a glyph.
enum SymbolNames {
    private static var validity: [String: Bool] = [:]

    static func resolved(_ name: String) -> String {
        if let known = validity[name] { return known ? name : "questionmark.circle" }
        let valid = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        validity[name] = valid
        return valid ? name : "questionmark.circle"
    }
}

// MARK: - Text measurement

/// Width of single-line labels in the system font, which is what SwiftUI's `Text` uses, so
/// tooltips can be sized and placed before layout. Cached per string and style.
enum LabelMetrics {
    private struct Key: Hashable {
        var text: String
        var size: CGFloat
        var weight: CGFloat
    }

    private static var cache: [Key: CGFloat] = [:]

    static func width(of text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let key = Key(text: text, size: size, weight: weight.rawValue)
        if let hit = cache[key] { return hit }
        if cache.count > 512 { cache.removeAll() }
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        cache[key] = width
        return width
    }
}
