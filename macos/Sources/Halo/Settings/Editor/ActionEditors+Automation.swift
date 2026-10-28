import AppKit
import HaloCore
import SwiftUI

// MARK: - Apple Shortcut

/// Name field with a menu of the user's shortcuts (from `ShortcutNames`), a found/missing
/// check, and the pass-selection option.
struct ShortcutActionEditor: View {
    @Binding var ref: ShortcutRef
    @Binding var setup: Bool
    var library: ShortcutNames = .shared

    var body: some View {
        let names = library.names
        LabeledContent("Shortcut") {
            HStack(spacing: 6) {
                CommittingTextField("Shortcut", text: $ref.name, prompt: "Shortcut name", focusRequest: $setup)
                    .labelsHidden()
                Menu {
                    if names.isEmpty {
                        Text(library.isLoading ? "Loading Shortcuts…" : "No Shortcuts Found")
                    }
                    ForEach(names, id: \.self) { name in
                        Toggle(name, isOn: Binding(get: { ref.name == name }, set: { if $0 { ref.name = name } }))
                    }
                    Divider()
                    Button("Refresh List", systemImage: "arrow.clockwise") { library.reload() }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose from your shortcuts")
                .accessibilityLabel("Choose a shortcut")
            }
        }
        statusRow(names)
        Toggle("Pass selected text as input", isOn: $ref.passSelection)
        Button("Open Shortcuts", systemImage: "square.2.layers.3d") {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                NSWorkspace.shared.open(url)
            }
        }
        .onAppear { library.loadIfNeeded() }
    }

    @ViewBuilder
    private func statusRow(_ names: [String]) -> some View {
        if library.isLoading, !library.hasLoaded {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading your shortcuts…").font(.caption).foregroundStyle(.secondary)
            }
        } else if ref.name.trimmingCharacters(in: .whitespaces).isEmpty {
            InspectorNote(.info, "Pick a shortcut from the list, or type its exact name.")
        } else if library.hasLoaded, !names.isEmpty, !names.contains(ref.name) {
            InspectorNote(.warning, "There's no shortcut named “\(ref.name)” in the Shortcuts app.")
        } else if names.contains(ref.name) {
            InspectorNote(.success, "Found in Shortcuts.")
        }
    }
}

// MARK: - Scripts

/// Monospaced script editor with a shell picker (shell scripts) and a "Run Now" test that shows
/// the outcome inline.
struct ScriptActionEditor: View {
    @Binding var source: ScriptSource
    let isShell: Bool
    @Binding var setup: Bool

    /// The script as typed, for Run Now before editing ends.
    @ViewState private var draft: String
    @ViewState private var run: RunState = .idle

    private enum RunState: Equatable {
        case idle
        case running
        case finished(ActionOutcome)
    }

    init(source: Binding<ScriptSource>, isShell: Bool, setup: Binding<Bool>) {
        self._source = source
        self.isShell = isShell
        self._setup = setup
        self._draft = ViewState(initialValue: source.wrappedValue.source)
    }

    var body: some View {
        EditorTextView(text: $source.source, draft: $draft, style: .code,
                       accessibilityLabel: isShell ? "Shell script" : "AppleScript", focusRequest: $setup)
            .editorTextBox(minHeight: 150)
        if isShell {
            Picker("Shell", selection: $source.shell) {
                Text("Login Shell").tag(String?.none)
                Divider()
                ForEach(Self.shells, id: \.self) { path in
                    Text("\((path as NSString).lastPathComponent) (\(path))").tag(String?.some(path))
                }
            }
        }
        HStack(spacing: 8) {
            Button("Run Now", systemImage: "play.fill", action: runNow)
                .disabled(run == .running || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Run the script now to test it")
            if run == .running {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Running")
            }
            Spacer(minLength: 0)
        }
        if case .finished(let outcome) = run {
            OutcomeNote(outcome: outcome)
        }
    }

    private func runNow() {
        if draft != source.source { source.source = draft }
        let script = ScriptSource(source: draft, shell: source.shell)
        let action: Action = isShell ? .shell(script) : .appleScript(script)
        let context = ActionContext(frontmostApp: nil, slotTitle: isShell ? "Shell Script" : "AppleScript", ringCenter: nil)
        run = .running
        Task { @MainActor in
            let outcome = await ActionRunner.shared.run(action, context: context)
            run = .finished(outcome)
            AccessibilityNotification.Announcement(OutcomeNote.message(for: outcome)).post()
        }
    }

    /// Shells listed in /etc/shells.
    private static let shells: [String] = {
        guard let text = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) else { return ["/bin/zsh", "/bin/bash", "/bin/sh"] }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") }
    }()
}

/// The result of a test run.
private struct OutcomeNote: View {
    let outcome: ActionOutcome

    var body: some View {
        switch outcome {
        case .success, .successWithMessage:
            InspectorNote(.success, Self.message(for: outcome))
        case .needsPermission(let permission):
            HStack {
                InspectorNote(.warning, Self.message(for: outcome))
                Spacer(minLength: 0)
                Button("Grant…") { PermissionCenter.shared.request(permission) }
                    .controlSize(.small)
            }
        case .failed:
            InspectorNote(.error, Self.message(for: outcome))
                .textSelection(.enabled)
        }
    }

    static func message(for outcome: ActionOutcome) -> String {
        switch outcome {
        case .success: "Ran successfully."
        case .successWithMessage(let message): message
        case .needsPermission(let permission): "Needs \(PermissionCenter.title(permission)) permission."
        case .failed(let reason): reason
        }
    }
}

// MARK: - Text snippet

/// Snippet text with placeholder chips, the paste/type method and the press-Return option.
struct TextSnippetEditor: View {
    @Binding var snippet: TextSnippet
    @Binding var setup: Bool

    /// A placeholder chip waiting to be inserted at the caret.
    @ViewState private var insertion: String?

    var body: some View {
        EditorTextView(text: $snippet.text, style: .prose, accessibilityLabel: "Snippet text",
                       focusRequest: $setup, insertion: $insertion)
            .editorTextBox(minHeight: 100)
        PlaceholderChips(placeholders: Placeholder.all) { insertion = $0 }
        Picker("Insert By", selection: $snippet.method) {
            Text("Pasting").tag(TextSnippet.Method.paste)
            Text("Typing").tag(TextSnippet.Method.type)
        }
        .pickerStyle(.segmented)
        InspectorNote(.info, snippet.method == .paste
            ? "Fast and exact. Your clipboard is put back afterwards."
            : "Types each character, for apps that block pasting. Slower for long text.")
        Toggle("Press Return afterwards", isOn: $snippet.pressReturn)
    }
}

// MARK: - AI prompt

/// Service picker, prompt template with a {selection} chip, and the custom URL for `.custom`.
struct AIPromptEditor: View {
    @Binding var prompt: AIPrompt
    @Binding var setup: Bool

    /// The prompt as typed, for the {selection} hint.
    @ViewState private var draft: String
    @ViewState private var insertion: String?

    init(prompt: Binding<AIPrompt>, setup: Binding<Bool>) {
        self._prompt = prompt
        self._setup = setup
        self._draft = ViewState(initialValue: prompt.wrappedValue.template)
    }

    var body: some View {
        Picker("Service", selection: $prompt.service) {
            ForEach(AIPrompt.Service.allCases, id: \.self) { service in
                Text(service.displayName).tag(service)
            }
        }
        if prompt.service == .custom {
            CommittingTextField("URL", text: customURL, prompt: "https://example.com/?q={prompt}")
            if !(prompt.customURLTemplate ?? "").contains("{prompt}") {
                InspectorNote(.error, "The URL must contain {prompt}, where Halo puts your prompt.")
            }
        }
        EditorTextView(text: $prompt.template, draft: $draft, style: .prose, accessibilityLabel: "Prompt",
                       focusRequest: $setup, insertion: $insertion)
            .editorTextBox(minHeight: 100)
        PlaceholderChips(placeholders: [Placeholder.selection]) { insertion = $0 }
        if !draft.contains("{selection}") {
            InspectorNote(.info, "Add {selection} to include the text selected in the front app.")
        }
    }

    private var customURL: Binding<String> {
        let prompt = $prompt
        return Binding(
            get: { prompt.wrappedValue.customURLTemplate ?? "" },
            set: { prompt.wrappedValue.customURLTemplate = $0.isEmpty ? nil : $0 }
        )
    }
}

extension AIPrompt.Service {
    var editorExplanation: String {
        switch self {
        case .chatGPT, .claude, .perplexity: "Opens \(displayName) with your prompt filled in."
        case .gemini: "Gemini can't be prefilled, so Halo copies the prompt and opens Gemini. Paste it with ⌘V."
        case .custom: "Opens your URL with {prompt} replaced by the prompt."
        }
    }
}

// MARK: - Placeholders

/// A text placeholder filled in when an action runs.
struct Placeholder: Hashable {
    var token: String
    var help: String

    static let date = Placeholder(token: "{date}", help: "Today's date")
    static let time = Placeholder(token: "{time}", help: "The current time")
    static let clipboard = Placeholder(token: "{clipboard}", help: "What's on the clipboard")
    static let selection = Placeholder(token: "{selection}", help: "The text selected in the front app")
    static let all = [date, time, clipboard, selection]
}

/// Buttons that insert placeholders into a text.
struct PlaceholderChips: View {
    let placeholders: [Placeholder]
    let onInsert: (String) -> Void

    var body: some View {
        EditorFlowLayout(spacing: 6) {
            ForEach(placeholders, id: \.self) { placeholder in
                Button {
                    onInsert(placeholder.token)
                } label: {
                    Text(placeholder.token)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(.tint)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Insert \(placeholder.help.lowercased())")
                .accessibilityLabel("Insert \(placeholder.token) placeholder")
                .accessibilityHint(placeholder.help)
            }
        }
    }
}
