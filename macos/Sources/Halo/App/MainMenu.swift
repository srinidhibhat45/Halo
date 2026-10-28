import AppKit

/// The main menu, visible while a Halo window is open (Halo is a regular app then).
///
/// Built in AppKit because Halo's windows are AppKit-managed: the Edit menu gives SwiftUI text
/// fields ⌘X/⌘C/⌘V/⌘Z, and the Window menu lists the open windows. Standard items target the
/// first responder; Halo's own items target `MenuActions`.
enum MainMenu {
    private static var menu: NSMenu?
    private static var windowMenu: NSMenu?
    private static var helpMenu: NSMenu?
    private static var servicesMenu: NSMenu?
    private static let actions = MenuActions()

    /// Installs the menu, or puts it back if something (such as SwiftUI's own menu management)
    /// replaced it. Cheap to call repeatedly.
    static func install() {
        let menu = menu ?? build()
        self.menu = menu
        guard NSApp.mainMenu !== menu else { return }
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
        NSApp.servicesMenu = servicesMenu
    }

    private static func build() -> NSMenu {
        let main = NSMenu(title: "Main Menu")
        let window = makeWindowMenu()
        let help = makeHelpMenu()
        for submenu in [makeAppMenu(), makeEditMenu(), window, help] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        windowMenu = window
        helpMenu = help
        return main
    }

    private static func makeAppMenu() -> NSMenu {
        let menu = NSMenu(title: "Halo")
        menu.addItem(item("About Halo", #selector(MenuActions.showAbout(_:)), target: actions))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(MenuActions.showSettings(_:)), key: ",", target: actions))
        menu.addItem(.separator())

        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        servicesMenu = services
        menu.addItem(servicesItem)
        menu.addItem(.separator())

        menu.addItem(item("Hide Halo", #selector(NSApplication.hide(_:)), key: "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Halo", #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private static func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        // `undo:`/`redo:` are implemented by NSWindow (and text views), not declared in Swift.
        menu.addItem(item("Undo", Selector(("undo:")), key: "z"))
        menu.addItem(item("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), key: "v", modifiers: [.command, .option, .shift]))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private static func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), key: "w"))
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func makeHelpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(item("Halo Welcome Guide", #selector(MenuActions.showWelcomeGuide(_:)), target: actions))
        return menu
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}

/// Targets for Halo's own main-menu items.
private final class MenuActions: NSObject {
    @objc func showAbout(_ sender: Any?) {
        SettingsRouter.shared.open(.about)
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsRouter.shared.open()
    }

    @objc func showWelcomeGuide(_ sender: Any?) {
        SettingsRouter.shared.openOnboarding()
    }
}
