import AppKit
import UniformTypeIdentifiers

/// Open panels for the configurator, shown as a sheet on the settings window when there is one.
enum EditorOpenPanel {
    /// Any application bundle, starting in /Applications.
    static func chooseApplication() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        return await present(panel)
    }

    /// Any file or folder.
    static func chooseFileOrFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a File or Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        return await present(panel)
    }

    /// An image file for a custom icon.
    static func chooseImage() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose an Icon Image"
        panel.prompt = "Use Image"
        panel.allowedContentTypes = [.image]
        return await present(panel)
    }

    private static func present(_ panel: NSOpenPanel) async -> URL? {
        panel.allowsMultipleSelection = false
        if let window = NSApp.mainWindow, window.isVisible {
            let response = await panel.beginSheetModal(for: window)
            return response == .OK ? panel.url : nil
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
