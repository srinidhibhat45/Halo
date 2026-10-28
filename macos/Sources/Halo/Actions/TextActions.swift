import AppKit
import HaloCore

/// Text snippets: paste (clipboard restored) or type, with placeholders.
enum TextActions {
    /// How long the target app gets to read the pasteboard before the old contents come back.
    private static let pasteSettle: Duration = .milliseconds(400)

    static func run(_ snippet: TextSnippet) async -> ActionOutcome {
        if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
        let text = await Placeholders.expand(snippet.text)
        guard !text.isEmpty || snippet.pressReturn else { return .failed("The snippet is empty") }
        await KeySender.waitForTriggerRelease()

        let sent: Bool
        switch snippet.method {
        case .paste where text.isEmpty, .type where text.isEmpty: sent = true
        case .paste: sent = await paste(text)
        case .type: sent = await KeySender.type(text)
        }
        guard sent else { return .failed("Couldn't send the text") }
        if snippet.pressReturn {
            try? await Task.sleep(for: .milliseconds(60))
            await KeySender.press(CGKeyCode(KeyCode.return), modifiers: [])
        }
        return .success
    }

    /// Puts `text` on the pasteboard, presses ⌘V and restores the previous contents.
    static func paste(_ text: String) async -> Bool {
        await ClipboardLock.run {
            let snapshot = Clipboard.Snapshot.capture()
            let ours = Clipboard.writeTransient(text)
            guard await KeySender.press(character: "v", modifiers: .maskCommand, fallback: CGKeyCode(KeyCode.v)) else { return false }
            try? await Task.sleep(for: pasteSettle)
            snapshot?.restore(ifChangeCountIs: ours)
            return true
        }
    }
}

/// `{date}`, `{time}`, `{clipboard}` and `{selection}` in snippet text.
enum Placeholders {
    private static let tokens = ["{date}", "{time}", "{clipboard}", "{selection}"]

    /// Replaces each placeholder in one pass (inserted text is never expanded again). The
    /// selection is read (⌘C) only when the text uses it.
    static func expand(_ text: String) async -> String {
        let used = tokens.filter { text.contains($0) }
        guard !used.isEmpty else { return text }
        var values: [String: String] = [:]
        if used.contains("{selection}") { values["{selection}"] = await SelectionReader.read() ?? "" }
        if used.contains("{clipboard}") { values["{clipboard}"] = await ClipboardLock.run { Clipboard.string ?? "" } }
        values["{date}"] = Date.now.formatted(date: .abbreviated, time: .omitted)
        values["{time}"] = Date.now.formatted(date: .omitted, time: .shortened)

        var result = ""
        var rest = text[...]
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let tail = rest[open...]
            if let token = used.first(where: { tail.hasPrefix($0) }), let value = values[token] {
                result += value
                rest = tail.dropFirst(token.count)
            } else {
                result += "{"
                rest = tail.dropFirst()
            }
        }
        return result + rest
    }
}
