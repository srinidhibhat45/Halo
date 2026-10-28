import AppKit

/// Offers to move Halo into Applications when it was opened straight from the disk image or from
/// Downloads. From there macOS runs a temporary read-only copy ("App Translocation"): Halo would
/// disappear when the disk image is ejected, couldn't start at login reliably and couldn't update
/// itself.
enum InstallLocation {
    private static let declinedKey = "InstallLocation.declinedMove"

    /// Why the current location is a problem, or nil when Halo is somewhere it can stay.
    static var problem: String? {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        if path.contains("/AppTranslocation/") {
            return "Halo is running from a temporary copy that macOS made because it was opened from the disk image or the Downloads folder."
        }
        if path.hasPrefix("/Volumes/"), (try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true {
            return "Halo is running from its disk image."
        }
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
           path.hasPrefix(downloads.resolvingSymlinksInPath().path + "/") {
            return "Halo is running from your Downloads folder."
        }
        return nil
    }

    /// Asks (until told not to) and, if the user agrees, copies Halo into Applications and arranges
    /// for the copy to open. Returns true when the caller must quit so the copy can take over.
    static func offerMoveIfNeeded() -> Bool {
        guard let problem, !UserDefaults.standard.bool(forKey: declinedKey) else { return false }
        let folder = destinationFolder
        let alert = NSAlert()
        alert.messageText = "Move Halo to Applications?"
        alert.informativeText = "\(problem) Move it to \(folder.path == "/Applications" ? "your Applications folder" : folder.path) so it keeps working, can start when you log in and can update itself."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        NSApp.activate()
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: declinedKey) }
        guard response == .alertFirstButtonReturn else { return false }

        do {
            let destination = try move(to: folder)
            Log.app.info("Moved Halo to \(destination.path, privacy: .public); relaunching")
            return true
        } catch {
            Log.app.error("Moving Halo failed: \(error.localizedDescription, privacy: .public)")
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "Halo Couldn't Move Itself"
            failure.informativeText = "\(error.localizedDescription)\n\nQuit Halo, drag it from the disk image onto the Applications folder, then open it from there."
            failure.addButton(withTitle: "OK")
            failure.runModal()
            return false
        }
    }

    /// /Applications when this user can write to it (admins), otherwise ~/Applications.
    private static var destinationFolder: URL {
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if FileManager.default.isWritableFile(atPath: system.path) { return system }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory)
    }

    /// Copies the running bundle into `folder` (an older Halo there goes to the Trash), and starts
    /// a helper that opens the copy once this process has quit and ejects the disk image.
    private static func move(to folder: URL) throws -> URL {
        let fm = FileManager.default
        let source = Bundle.main.bundleURL
        let destination = folder.appending(path: "Halo.app", directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        if fm.fileExists(atPath: destination.path) {
            let existing = Bundle(url: destination)?.bundleIdentifier
            guard existing == Bundle.main.bundleIdentifier else {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: "There is already a different app called Halo in \(folder.path)."])
            }
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        try fm.copyItem(at: source, to: destination)
        // The user already chose to open this copy; without this macOS would quarantine and
        // translocate the new copy again.
        let strip = Process()
        strip.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        strip.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try strip.run()
        strip.waitUntilExit()

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", relaunchScript, "sh", String(ProcessInfo.processInfo.processIdentifier), destination.path, diskImageVolume?.path ?? ""]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()   // not waited for: it outlives Halo
        return destination
    }

    /// The mounted disk image Halo came from: a read-only volume holding this same app.
    private static var diskImageVolume: URL? {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsReadOnlyKey], options: [.skipHiddenVolumes]) ?? []
        return volumes.first { volume in
            guard volume.path.hasPrefix("/Volumes/"),
                  (try? volume.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true else { return false }
            return Bundle(url: volume.appending(path: "Halo.app"))?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
    }

    /// Waits (≤ 30 s) for Halo to quit, opens the moved copy and ejects the disk image, if any.
    private static let relaunchScript = """
    PID="$1"; APP="$2"; VOLUME="$3"
    i=0
    while kill -0 "$PID" 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done
    /usr/bin/open "$APP"
    if [ -n "$VOLUME" ]; then sleep 1; /usr/bin/hdiutil detach "$VOLUME" -quiet || true; fi
    """
}
