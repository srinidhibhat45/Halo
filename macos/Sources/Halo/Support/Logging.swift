import Foundation
import os

/// Unified logging categories. View with: log stream --predicate 'subsystem == "com.srinidhibhat.Halo"'
nonisolated enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.srinidhibhat.Halo"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let trigger = Logger(subsystem: subsystem, category: "trigger")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let actions = Logger(subsystem: subsystem, category: "actions")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
}
