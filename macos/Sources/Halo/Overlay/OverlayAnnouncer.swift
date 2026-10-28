import AppKit

/// Speaks short status messages through VoiceOver. The ring and toasts never take focus, so
/// VoiceOver wouldn't otherwise notice the highlight moving or a toast appearing.
enum OverlayAnnouncer {
    static func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .high) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: priority.rawValue,
        ])
    }
}
