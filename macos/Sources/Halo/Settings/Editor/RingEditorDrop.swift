import AppKit
import CoreTransferable
import HaloCore

/// Drag payloads the ring editor produces, encoded as plain strings (`String` is `Transferable`
/// without declaring a custom UTType).
enum EditorDragToken {
    private static let templatePrefix = "halo-template:"
    private static let appPrefix = "halo-app:"
    private static let shortcutPrefix = "halo-shortcut:"
    private static let slotPrefix = "halo-slot:"

    enum Payload {
        /// A library template.
        case template(ActionTemplate)
        /// An installed app.
        case app(AppInfo)
        /// One of the user's Apple Shortcuts, by name.
        case shortcut(String)
        /// A slot of the ring being edited (drag to swap).
        case slot(Slot.ID)
    }

    static func template(_ id: String) -> String { templatePrefix + id }
    static func app(_ bundleID: String) -> String { appPrefix + bundleID }
    static func shortcut(_ name: String) -> String { shortcutPrefix + name }
    static func slot(_ id: Slot.ID) -> String { slotPrefix + id.uuidString }

    static func decode(_ text: String) -> Payload? {
        if let id = text.dropPrefix(templatePrefix) {
            return ActionCatalog.template(id: id).map(Payload.template)
        }
        if let bundleID = text.dropPrefix(appPrefix) {
            return AppCatalog.shared.info(bundleID: bundleID).map(Payload.app)
        }
        if let name = text.dropPrefix(shortcutPrefix), !name.isEmpty {
            return .shortcut(name)
        }
        if let raw = text.dropPrefix(slotPrefix) {
            return UUID(uuidString: raw).map(Payload.slot)
        }
        return nil
    }
}

/// What can be dropped on the ring canvas: the editor's own string tokens, plus files, apps and
/// links dragged in from Finder or a browser.
enum RingDropItem: Transferable {
    case text(String)
    case url(URL)

    /// What a drop means for the ring.
    enum Resolved {
        /// Swap (or, with ⌥, copy) a slot of the shown ring.
        case slot(Slot.ID)
        /// New content for the target slot.
        case content(Slot, needsSetup: Bool)
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (url: URL) in RingDropItem.url(url) })
        ProxyRepresentation(importing: { (text: String) in RingDropItem.text(text) })
    }

    /// Decoded on the main actor: tokens look up the catalog and installed apps.
    @MainActor var resolved: Resolved? {
        switch self {
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let payload = EditorDragToken.decode(trimmed) { return Self.resolve(payload) }
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
                let expanded = (trimmed as NSString).expandingTildeInPath
                guard FileManager.default.fileExists(atPath: expanded) else { return nil }
                return Self.resolve(fileURL: URL(fileURLWithPath: expanded))
            }
            guard let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty, !trimmed.contains(" ") else { return nil }
            return .content(Slot(action: .url(WebLink(url: trimmed))), needsSetup: false)
        case .url(let url):
            if url.isFileURL { return Self.resolve(fileURL: url) }
            if url.scheme?.hasPrefix("halo-") == true {
                return EditorDragToken.decode(url.absoluteString).flatMap(Self.resolve)
            }
            return .content(Slot(action: .url(WebLink(url: url.absoluteString))), needsSetup: false)
        }
    }

    @MainActor private static func resolve(_ payload: EditorDragToken.Payload) -> Resolved {
        switch payload {
        case .template(let template): .content(template.editorSlot(), needsSetup: template.needsSetup)
        case .app(let app): .content(app.editorSlot(), needsSetup: false)
        case .shortcut(let name): .content(Slot(action: .shortcut(ShortcutRef(name: name))), needsSetup: false)
        case .slot(let id): .slot(id)
        }
    }

    @MainActor private static func resolve(fileURL url: URL) -> Resolved? {
        if url.pathExtension.lowercased() == "app", let app = AppCatalog.appInfo(at: url) {
            return .content(app.editorSlot(), needsSetup: false)
        }
        let path = (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        return .content(Slot(action: .file(FileTarget(path: path))), needsSetup: false)
    }
}

extension ActionTemplate {
    /// A slot for this template. Ready-made templates keep the library's title and symbol when
    /// they say more than the action's defaults (e.g. "Summarize" rather than "Ask Claude").
    func editorSlot() -> Slot {
        var slot = Slot(action: action)
        if case .folder(let ring) = action { slot.action = .folder(AppModel.freshIDs(ring)) }
        guard !needsSetup else { return slot }
        if title != action.defaultTitle { slot.title = title }
        if case .symbol = action.defaultIcon, symbol != action.defaultSymbol { slot.icon = .symbol(name: symbol) }
        return slot
    }
}

extension AppInfo {
    /// A slot that opens this app.
    func editorSlot() -> Slot {
        Slot(action: .app(AppTarget(bundleID: bundleID, name: name, path: url.path(percentEncoded: false))))
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
