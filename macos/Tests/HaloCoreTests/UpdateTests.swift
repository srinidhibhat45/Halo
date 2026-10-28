import Foundation
import Testing
@testable import HaloCore

@Suite("Updates")
struct UpdateTests {
    @Test("Versions parse with or without v, short forms and pre-releases")
    func parse() {
        #expect(SemanticVersion("v1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion("1.2") == SemanticVersion(major: 1, minor: 2))
        #expect(SemanticVersion("2.0.0-beta.1")?.prerelease == "beta.1")
        #expect(SemanticVersion("1.0.0+build.7") == SemanticVersion(major: 1))
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("1.x") == nil)
        #expect(SemanticVersion("1.2.3.4") == nil)
        #expect(SemanticVersion("1.0.0-") == nil)
    }

    @Test("Ordering follows SemVer, pre-releases below releases")
    func order() {
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "2.0.0"]
            .compactMap(SemanticVersion.init)
        #expect(ordered.count == 11)
        #expect(ordered == ordered.sorted())
        #expect(SemanticVersion("1.10.0")! > SemanticVersion("1.9.9")!)
    }

    private func release(_ tag: String, draft: Bool = false, pre: Bool = false, assets: [String] = ["Halo-x-mac.zip", "Halo-x-mac.zip.sha256", "Halo-x-mac.dmg"]) -> GitHubRelease {
        GitHubRelease(tagName: tag, pageURL: URL(string: "https://github.com/srinidhibhat45/Halo/releases/tag/\(tag)")!,
                      isDraft: draft, isPrerelease: pre,
                      assets: assets.map { .init(name: $0, downloadURL: URL(string: "https://example.com/\($0)")!, size: 1) })
    }

    @Test("Newer stable releases with a payload are available; others are not")
    func evaluate() {
        let current = SemanticVersion("1.0.0")!
        #expect(UpdatePolicy.evaluate(release("v1.1.0"), current: current, skipped: nil) == .available(SemanticVersion("1.1.0")!))
        #expect(UpdatePolicy.evaluate(release("v1.0.0"), current: current, skipped: nil) == .upToDate)
        #expect(UpdatePolicy.evaluate(release("v0.9.0"), current: current, skipped: nil) == .upToDate)
        #expect(UpdatePolicy.evaluate(release("v2.0.0", draft: true), current: current, skipped: nil) == .upToDate)
        #expect(UpdatePolicy.evaluate(release("v2.0.0", pre: true), current: current, skipped: nil) == .upToDate)
        #expect(UpdatePolicy.evaluate(release("v1.1.0", assets: ["Halo-x-mac.dmg"]), current: current, skipped: nil) == .notInstallable)
        #expect(UpdatePolicy.evaluate(release("v1.1.0"), current: current, skipped: "1.1.0") == .skipped(SemanticVersion("1.1.0")!))
    }

    @Test("GitHub's JSON decodes")
    func decode() throws {
        let json = """
        {"tag_name":"v1.4.0","name":"Halo 1.4","body":"Notes","html_url":"https://github.com/srinidhibhat45/Halo/releases/tag/v1.4.0",
         "draft":false,"prerelease":false,"assets":[
          {"name":"Halo-1.4.0-mac.zip","browser_download_url":"https://github.com/srinidhibhat45/Halo/releases/download/v1.4.0/Halo-1.4.0-mac.zip","size":4200000},
          {"name":"Halo-1.4.0-mac.zip.sha256","browser_download_url":"https://github.com/srinidhibhat45/Halo/releases/download/v1.4.0/Halo-1.4.0-mac.zip.sha256","size":90},
          {"name":"HaloSetup.exe","browser_download_url":"https://github.com/srinidhibhat45/Halo/releases/download/v1.4.0/HaloSetup.exe","size":50000000}]}
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(release.version == SemanticVersion("1.4.0"))
        #expect(release.macUpdateArchive?.size == 4_200_000)
        #expect(release.macUpdateChecksum != nil)
        #expect(release.macInstaller == nil)
    }

    @Test("Checksums parse from shasum output")
    func checksum() {
        let hex = String(repeating: "aB3", count: 21) + "f"
        #expect(UpdatePolicy.parseChecksum("\(hex)  Halo-1.0.0-mac.zip\n") == hex.lowercased())
        #expect(UpdatePolicy.parseChecksum("not a checksum") == nil)
        #expect(UpdatePolicy.parseChecksum("") == nil)
    }
}
