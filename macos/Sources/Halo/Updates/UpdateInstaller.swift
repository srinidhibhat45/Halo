import CryptoKit
import Foundation
import HaloCore

/// Downloads, verifies and installs an update, off the main actor.
///
/// An update is the release's `Halo-<version>-mac.zip` (the app bundle, zipped with `ditto`)
/// plus its `.sha256`. It is installed only if the checksum matches, the bundle identifier and
/// version are the expected ones and the code signature is intact. A small shell helper swaps the
/// bundles once Halo has quit, keeps the old copy if anything fails, and relaunches.
nonisolated enum UpdateInstaller {
    enum Failure: LocalizedError {
        case download(String)
        case checksumMismatch
        case badChecksumFile
        case unpack
        case wrongApp(String)
        case signature
        /// Halo can't write to the folder it runs from (e.g. /Applications without admin rights).
        case notWritable(URL)

        var errorDescription: String? {
            switch self {
            case .download(let reason): "The download failed: \(reason)"
            case .checksumMismatch: "The download didn't match its published checksum, so it wasn't installed."
            case .badChecksumFile: "The release's checksum file is unreadable."
            case .unpack: "The update couldn't be unpacked."
            case .wrongApp(let reason): "The update isn't a valid Halo app (\(reason))."
            case .signature: "The update's code signature is broken."
            case .notWritable(let folder): "Halo can't replace itself in \(folder.path)."
            }
        }
    }

    /// Where updates are staged: ~/Library/Caches/Halo/Updates/<version>.
    static func stagingDirectory(for version: SemanticVersion) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appending(path: "Halo/Updates/\(version)", directoryHint: .isDirectory)
    }

    /// Downloads and verifies the update; returns the unpacked, verified `Halo.app`.
    static func prepare(archive: URL, checksum: URL, version: SemanticVersion, bundleIdentifier: String) async throws -> URL {
        let directory = stagingDirectory(for: version)
        let fm = FileManager.default
        try? fm.removeItem(at: directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let expected: String
        do {
            let (data, response) = try await URLSession.shared.data(from: checksum)
            try requireOK(response)
            guard let text = String(data: data, encoding: .utf8), let sum = UpdatePolicy.parseChecksum(text) else { throw Failure.badChecksumFile }
            expected = sum
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.download(error.localizedDescription)
        }

        let zip = directory.appending(path: "Halo.zip")
        do {
            let (temporary, response) = try await URLSession.shared.download(from: archive)
            try requireOK(response)
            try fm.moveItem(at: temporary, to: zip)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.download(error.localizedDescription)
        }

        guard try sha256(of: zip) == expected else { throw Failure.checksumMismatch }

        let unpacked = directory.appending(path: "unpacked", directoryHint: .isDirectory)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else { throw Failure.unpack }
        let app = unpacked.appending(path: "Halo.app", directoryHint: .isDirectory)
        guard let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) as? [String: Any] else {
            throw Failure.wrongApp("no Info.plist")
        }
        guard info["CFBundleIdentifier"] as? String == bundleIdentifier else { throw Failure.wrongApp("different bundle identifier") }
        guard let shown = info["CFBundleShortVersionString"] as? String, SemanticVersion(shown) == version else {
            throw Failure.wrongApp("version doesn't match the release")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else { throw Failure.signature }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    /// Starts the helper that replaces `destination` with `newApp` after process `pid` exits,
    /// then relaunches it. The caller must quit right after this returns.
    static func scheduleReplacement(of destination: URL, with newApp: URL, afterExitOf pid: Int32) throws {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path), fm.isWritableFile(atPath: destination.path) else {
            throw Failure.notWritable(parent)
        }
        let script = newApp.deletingLastPathComponent().deletingLastPathComponent().appending(path: "install.sh")
        try helperScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(pid), newApp.path, destination.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()   // not waited for: it outlives Halo
    }

    /// Waits for Halo to quit (≤ 30 s), swaps the bundles keeping a backup until the new one is
    /// in place, restores the old one on failure, and opens whichever is installed.
    private static let helperScript = """
    #!/bin/sh
    PID="$1"; NEW="$2"; DEST="$3"; BACKUP="$DEST.previous"
    i=0
    while kill -0 "$PID" 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done
    rm -rf "$BACKUP"
    if mv "$DEST" "$BACKUP"; then
      if /usr/bin/ditto "$NEW" "$DEST"; then
        rm -rf "$BACKUP"
      else
        rm -rf "$DEST"; mv "$BACKUP" "$DEST"
      fi
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
    /usr/bin/open "$DEST"
    """

    private static func requireOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw Failure.download("server answered \(code)")
        }
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
