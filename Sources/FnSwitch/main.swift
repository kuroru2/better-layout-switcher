import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    let detector = FnTapDetector()
    let osd = OSDWindow()
    var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()

        detector.onTap = { [self] in
            if let name = LayoutManager.switchToNext() {
                print("Switched to: \(name)")
                osd.show(text: name)
                statusBar.updateTitle()
            }
        }

        LayoutManager.printAvailableSources()
        detector.start()
    }
}

// --- Entry point ---
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
