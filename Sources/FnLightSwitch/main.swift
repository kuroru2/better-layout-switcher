import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    let detector = FnTapDetector()
    let osd = OSDWindow()
    let xdr = XDRBoostController()
    let xdrOSD = XDROSDWindow()
    let xdrKeyTap = XDRKeyTap()
    var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: Settings.defaults)

        XDRBoostController.shared = xdr
        xdr.osd = xdrOSD
        statusBar = StatusBarController(xdr: xdr)

        detector.onTap = { [self] in
            guard Settings.languageSwitchEnabled else { return }
            if let name = LayoutManager.switchToNext() {
                print("Switched to: \(name)")
                osd.show(text: name)
                statusBar.updateTitle()
            }
        }

        // Brightness-key interception: pass-through unless XDR boost is
        // engaged AND user is already at max system brightness.
        xdrKeyTap.onBrightnessUp = { [weak self] in
            self?.xdr.handleBrightnessUpKey() ?? false
        }
        xdrKeyTap.onBrightnessDown = { [weak self] in
            self?.xdr.handleBrightnessDownKey() ?? false
        }
        xdrKeyTap.start()

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
