import Foundation

/// Text typed in the editor that hasn't been written to the configuration yet.
///
/// Text fields and editors keep a draft while focused and write it when editing ends, so a
/// burst of typing is one undo step. Structural edits (clear, replace, move, drop, resize…) call
/// `commitAll()` first: the draft is written to the slot it was typed for before that slot
/// changes, never afterwards over whatever replaced it.
enum PendingEdits {
    private static var commits: [UUID: () -> Void] = [:]

    /// Registers the commit of an editor that started editing. Commits must be idempotent (write
    /// only when the draft differs from the model).
    static func register(_ id: UUID, commit: @escaping () -> Void) {
        commits[id] = commit
    }

    static func unregister(_ id: UUID) {
        commits[id] = nil
    }

    /// Writes every pending draft now, each as its own undo step.
    static func commitAll() {
        for commit in commits.values { commit() }
    }
}
