import Foundation

/// Reading and writing `HaloConfig` as JSON.
///
/// Layout in `~/Library/Application Support/Halo/`:
/// - `config.json`: the live config, written atomically.
/// - `config.backup.json`: the previous version, rotated on every save.
/// - `config.unreadable-<timestamp>.json`: a config that failed to decode, set aside (never deleted).
public enum ConfigFile {
    public static let fileExtension = "json"
    public static let exportExtension = "haloring"

    public enum LoadOutcome: Equatable, Sendable {
        /// Loaded the saved config.
        case loaded
        /// No config yet: started from defaults.
        case createdDefault
        /// The config could not be read; it was set aside at `movedTo` and defaults were used.
        case recoveredFromCorruption(movedTo: URL)
        /// The config could not be read nor moved; defaults are in use and saving is unsafe.
        case unreadable(String)
    }

    /// `~/Library/Application Support/Halo/`
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: "Halo", directoryHint: .isDirectory)
    }

    public static var defaultURL: URL { directory.appending(path: "config.json") }
    public static func backupURL(for url: URL) -> URL { url.deletingLastPathComponent().appending(path: "config.backup.json") }

    // MARK: Encoding

    public static func encode(_ config: HaloConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config)
    }

    public static func decode(_ data: Data) throws -> HaloConfig {
        try JSONDecoder().decode(HaloConfig.self, from: data)
    }

    // MARK: Disk

    /// Loads the config at `url`, falling back to defaults (and setting a broken file aside).
    public static func load(from url: URL = defaultURL) -> (HaloConfig, LoadOutcome) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return (.default, .createdDefault) }
        do {
            let data = try Data(contentsOf: url)
            return (try decode(data), .loaded)
        } catch {
            // Try the backup before giving up on the user's setup.
            let backup = backupURL(for: url)
            let backupConfig = (try? Data(contentsOf: backup)).flatMap { try? decode($0) }
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = url.deletingLastPathComponent().appending(path: "config.unreadable-\(stamp).json")
            do {
                try fm.moveItem(at: url, to: aside)
                return (backupConfig ?? .default, .recoveredFromCorruption(movedTo: aside))
            } catch {
                return (backupConfig ?? .default, .unreadable(error.localizedDescription))
            }
        }
    }

    /// Writes atomically, keeping the previous file as `config.backup.json`.
    public static func save(_ config: HaloConfig, to url: URL = defaultURL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encode(config)
        if fm.fileExists(atPath: url.path) {
            let backup = backupURL(for: url)
            // Only rotate when the content changes, so the backup stays one real edit behind.
            if let old = try? Data(contentsOf: url), old != data {
                try? fm.removeItem(at: backup)
                try? fm.copyItem(at: url, to: backup)
            }
        }
        try data.write(to: url, options: [.atomic])
    }

    // MARK: Import / export

    /// Data for "Export…" (same JSON as the live file).
    public static func exportData(_ config: HaloConfig) throws -> Data { try encode(config) }

    /// Parses an exported file. Throws a readable error for files that aren't Halo configs.
    public static func importConfig(from data: Data) throws -> HaloConfig {
        do {
            return try decode(data)
        } catch {
            throw ImportError.notAHaloConfig(underlying: String(describing: error))
        }
    }

    public enum ImportError: LocalizedError, Sendable {
        case notAHaloConfig(underlying: String)

        public var errorDescription: String? {
            switch self {
            case .notAHaloConfig: "This file isn't a Halo configuration."
            }
        }
    }
}
