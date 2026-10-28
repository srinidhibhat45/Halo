import AppKit
import HaloCore

/// "Ask AI": fill the prompt with the selection and open the service with it prefilled, or copy it
/// and open the site when the service has no prefill URL.
enum AIPromptActions {
    /// Longer URLs are truncated or rejected by some browsers and services.
    private static let maxURLLength = 8000

    /// Only unreserved characters survive unencoded in the `{prompt}` value.
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func run(_ prompt: AIPrompt) async -> ActionOutcome {
        var text = prompt.template
        if prompt.usesSelection {
            if let missing = PermissionCenter.shared.gate(.accessibility) { return missing }
            let selection = await SelectionReader.read()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !selection.isEmpty else { return .failed("Select some text first") }
            text = text.replacingOccurrences(of: "{selection}", with: selection)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failed("The prompt is empty") }

        let template = urlTemplate(for: prompt)
        if let template, let url = prefilledURL(template, prompt: text) {
            return await open(url, service: prompt.service)
        }
        // No prefill (or too long for a URL): hand the prompt over through the clipboard.
        await ClipboardLock.run { Clipboard.write(text) }
        if let home = homeURL(for: prompt, template: template) {
            let outcome = await open(home, service: prompt.service)
            if case .failed = outcome { return outcome }
        }
        return .successWithMessage("Prompt copied — paste it")
    }

    private static func urlTemplate(for prompt: AIPrompt) -> String? {
        let template = prompt.service == .custom ? prompt.customURLTemplate : prompt.service.urlTemplate
        guard let template = template?.trimmingCharacters(in: .whitespacesAndNewlines), !template.isEmpty else { return nil }
        return template
    }

    private static func prefilledURL(_ template: String, prompt: String) -> URL? {
        guard template.contains("{prompt}"),
              let encoded = prompt.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        let string = template.replacingOccurrences(of: "{prompt}", with: encoded)
        guard string.count <= maxURLLength else { return nil }
        return URL(string: string)
    }

    /// The service's start page; for a custom service, its URL without the placeholder.
    private static func homeURL(for prompt: AIPrompt, template: String?) -> URL? {
        let home = prompt.service == .custom
            ? template?.replacingOccurrences(of: "{prompt}", with: "")
            : prompt.service.homeURL
        guard let home, !home.isEmpty else { return nil }
        return AppActions.normalizedURL(home)
    }

    private static func open(_ url: URL, service: AIPrompt.Service) async -> ActionOutcome {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            return .success
        } catch {
            Log.actions.error("Open \(service.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return .failed("Couldn't open \(service == .custom ? "the AI site" : service.displayName)")
        }
    }
}
