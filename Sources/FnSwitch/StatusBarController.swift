import Cocoa

class StatusBarController {
    private var statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = LayoutManager.currentShortName
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Quit FnSwitch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    func updateTitle() {
        statusItem.button?.title = LayoutManager.currentShortName
    }
}
