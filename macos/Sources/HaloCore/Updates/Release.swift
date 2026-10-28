import Foundation

/// A semantic version ("1.2.3", "v1.2", "1.3.0-beta.2").
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    /// Pre-release identifiers ("beta.2"), nil for a release.
    public var prerelease: String?

    public init(major: Int, minor: Int = 0, patch: Int = 0, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Parses "1.2.3", "v1.2.3", "1.2" or "1.2.3-beta.1"; build metadata ("+abc") is ignored.
    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        if let plus = text.firstIndex(of: "+") { text = String(text[..<plus]) }
        var pre: String?
        if let dash = text.firstIndex(of: "-") {
            pre = String(text[text.index(after: dash)...])
            text = String(text[..<dash])
            if pre?.isEmpty == true { return nil }
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        self.init(major: parts[0] ?? 0, minor: parts.count > 1 ? parts[1] ?? 0 : 0, patch: parts.count > 2 ? parts[2] ?? 0 : 0, prerelease: pre)
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        switch (a.prerelease, b.prerelease) {
        case (nil, nil), (nil, _?): return false        // a release outranks its pre-releases
        case (_?, nil): return true
        case let (x?, y?): return comparePrerelease(x, y)
        }
    }

    /// SemVer §11: dot-separated identifiers, numeric ones compared numerically and ranked lower.
    private static func comparePrerelease(_ a: String, _ b: String) -> Bool {
        let xs = a.split(separator: "."), ys = b.split(separator: ".")
        for (x, y) in zip(xs, ys) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return x < y
            }
        }
        return xs.count < ys.count
    }
}

/// The parts of a GitHub release (REST API v3) that the updater needs.
public struct GitHubRelease: Decodable, Hashable, Sendable {
    public struct Asset: Decodable, Hashable, Sendable {
        public var name: String
        public var downloadURL: URL
        public var size: Int

        private enum CodingKeys: String, CodingKey {
            case name, size
            case downloadURL = "browser_download_url"
        }

        public init(name: String, downloadURL: URL, size: Int) {
            self.name = name
            self.downloadURL = downloadURL
            self.size = size
        }
    }

    public var tagName: String
    public var name: String?
    /// Release notes (Markdown).
    public var body: String?
    public var pageURL: URL
    public var isDraft: Bool
    public var isPrerelease: Bool
    public var assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case name, body, assets
        case tagName = "tag_name"
        case pageURL = "html_url"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
    }

    public init(tagName: String, name: String? = nil, body: String? = nil, pageURL: URL, isDraft: Bool = false, isPrerelease: Bool = false, assets: [Asset]) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.pageURL = pageURL
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.assets = assets
    }

    public var version: SemanticVersion? { SemanticVersion(tagName) }

    /// Release asset naming convention (see Scripts/package-release.sh):
    /// `Halo-<version>-mac.zip` (update payload), `…-mac.zip.sha256`, `Halo-<version>-mac.dmg`.
    public var macUpdateArchive: Asset? { assets.first { $0.name.hasSuffix("-mac.zip") } }
    public var macUpdateChecksum: Asset? { assets.first { $0.name.hasSuffix("-mac.zip.sha256") } }
    public var macInstaller: Asset? { assets.first { $0.name.hasSuffix("-mac.dmg") } }
}

/// Pure decisions for the updater.
public enum UpdatePolicy {
    public enum Decision: Equatable, Sendable {
        case upToDate
        /// A newer version the user previously chose to skip (shown only when checking by hand).
        case skipped(SemanticVersion)
        case available(SemanticVersion)
        /// The release has no macOS update payload yet (e.g. still uploading).
        case notInstallable
    }

    /// Whether `release` is an update for `current`. Drafts and pre-releases never are.
    public static func evaluate(_ release: GitHubRelease, current: SemanticVersion, skipped: String?) -> Decision {
        guard !release.isDraft, !release.isPrerelease, let version = release.version, current < version else { return .upToDate }
        guard release.macUpdateArchive != nil, release.macUpdateChecksum != nil else { return .notInstallable }
        if let skipped, SemanticVersion(skipped) == version { return .skipped(version) }
        return .available(version)
    }

    /// The SHA-256 in a `shasum -a 256` style file ("<hex>  <name>"), lowercased.
    public static func parseChecksum(_ text: String) -> String? {
        let token = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)?.lowercased()
        guard let token, token.count == 64, token.allSatisfy({ $0.isHexDigit }) else { return nil }
        return token
    }
}
