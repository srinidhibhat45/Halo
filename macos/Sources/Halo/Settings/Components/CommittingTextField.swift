import AppKit
import SwiftUI

/// A text field that edits a local draft and writes it back when editing ends (Return, focus
/// loss, the field going away, or a structural edit through `PendingEdits`), so a burst of
/// typing becomes one undo step in `AppModel` instead of one per keystroke.
///
/// Changes made elsewhere while the field is focused (a menu choice, a "Use https://" fix-up,
/// undo) replace the draft, so a stale draft never overwrites them when the field loses focus.
struct CommittingTextField: View {
    private let title: String
    @Binding private var text: String
    private let prompt: String?
    private let focusRequest: Binding<Bool>?

    @ViewState private var draft: String
    @ViewState private var editID = UUID()
    @FocusState private var isFocused: Bool

    /// - Parameter focusRequest: when it becomes true, the field takes keyboard focus and resets it.
    init(_ title: String, text: Binding<String>, prompt: String? = nil, focusRequest: Binding<Bool>? = nil) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.focusRequest = focusRequest
        self._draft = ViewState(initialValue: text.wrappedValue)
    }

    var body: some View {
        TextField(title, text: $draft, prompt: prompt.map { Text($0) })
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: text) { _, newValue in draft = newValue }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    PendingEdits.register(editID, commit: commit)
                } else {
                    commit()
                    PendingEdits.unregister(editID)
                }
            }
            .onDisappear {
                commit()
                PendingEdits.unregister(editID)
            }
            .onChange(of: focusRequest?.wrappedValue ?? false, initial: true) { _, requested in
                guard requested else { return }
                focusRequest?.wrappedValue = false
                // One turn later, so the field is in the window when it asks for focus.
                Task { @MainActor in isFocused = true }
            }
    }

    private func commit() {
        if draft != text { text = draft }
    }
}

/// A bordered, scrolling multi-line text editor (`NSTextView`) for scripts, snippets and prompts.
///
/// - Typing has its own undo stack: it never lands on `AppModel`'s (the window's) undo manager,
///   where it would later replay against text an edit or undo had replaced.
/// - Edits a draft and writes `text` when editing ends, when the view goes away, or on
///   `PendingEdits.commitAll()`.
/// - Adopts outside changes to `text` (undo, another editor) even while focused, discarding
///   its own typing history.
/// - Smart quotes, dashes and text replacement are off, so code and snippets stay exact.
struct EditorTextView: NSViewRepresentable {
    enum Style {
        /// Monospaced, no spell checking.
        case code
        /// The system font, with spell checking.
        case prose
    }

    /// The model value; written when editing ends.
    @Binding var text: String
    /// Mirrors every keystroke, for views that react to the text being typed.
    var draft: Binding<String>?
    var style: Style
    var accessibilityLabel: String
    /// When it becomes true, the text view takes keyboard focus and resets it.
    var focusRequest: Binding<Bool>?
    /// When set, the text is inserted at the selection (or caret) and the request reset.
    var insertion: Binding<String?>?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            textView.font = style == .code
                ? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                : .systemFont(ofSize: NSFont.systemFontSize)
            textView.textColor = .textColor
            textView.isRichText = false
            textView.importsGraphics = false
            textView.allowsUndo = true
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = style == .prose
            textView.isAutomaticLinkDetectionEnabled = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 4, height: 6)
            textView.string = text
            textView.setAccessibilityLabel(accessibilityLabel)
        }
        context.coordinator.committed = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.adopt(text, in: textView)
        if let focusRequest, focusRequest.wrappedValue {
            // Outside the view update: reset the request and focus once the view is in a window.
            Task { @MainActor in
                focusRequest.wrappedValue = false
                textView.window?.makeFirstResponder(textView)
            }
        }
        if let insertion, let token = insertion.wrappedValue {
            Task { @MainActor in
                insertion.wrappedValue = nil
                coordinator.insert(token, into: textView)
            }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.endEditing(scrollView.documentView as? NSTextView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        /// The model text this view last wrote or adopted.
        var committed = ""
        private let typingUndo = UndoManager()
        private let editID = UUID()

        init(_ parent: EditorTextView) {
            self.parent = parent
        }

        func undoManager(for view: NSTextView) -> UndoManager? { typingUndo }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            PendingEdits.register(editID) { [weak self, weak textView] in self?.commit(textView) }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.draft?.wrappedValue = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            endEditing(notification.object as? NSTextView)
        }

        func endEditing(_ textView: NSTextView?) {
            commit(textView)
            PendingEdits.unregister(editID)
        }

        /// Writes the text view's text to the model if it changed.
        func commit(_ textView: NSTextView?) {
            guard let textView, textView.string != committed else { return }
            committed = textView.string
            parent.text = textView.string
        }

        /// Takes a model change made elsewhere; the typing history no longer matches the text.
        func adopt(_ text: String, in textView: NSTextView) {
            guard text != committed else { return }
            committed = text
            guard textView.string != text else { return }
            textView.string = text
            typingUndo.removeAllActions()
            let draft = parent.draft
            Task { @MainActor in draft?.wrappedValue = text }
        }

        /// Inserts `token` at the selection as one undoable typing step, then writes the text.
        func insert(_ token: String, into textView: NSTextView) {
            let range = textView.selectedRange()
            guard textView.shouldChangeText(in: range, replacementString: token) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: token)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + (token as NSString).length, length: 0))
            commit(textView)
            textView.window?.makeFirstResponder(textView)
        }
    }
}

/// The rounded, bordered box text editors sit in.
struct EditorTextBox: ViewModifier {
    var minHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(minHeight: minHeight, idealHeight: minHeight)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
    }
}

extension View {
    func editorTextBox(minHeight: CGFloat = 110) -> some View {
        modifier(EditorTextBox(minHeight: minHeight))
    }
}
