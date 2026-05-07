import Cocoa
import ServiceManagement

class StatusBarController {
    private var statusItem: NSStatusItem
    private var launchAtLoginItem: NSMenuItem!
    private let xdr: XDRBoostController
    private var xdrSwitch: NSSwitch!
    private var xdrSlider: NSSlider!
    private var xdrValueLabel: NSTextField!

    init(xdr: XDRBoostController) {
        self.xdr = xdr
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = LayoutManager.currentShortName
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        }

        let menu = NSMenu()

        launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem()
        toggleItem.view = makeToggleView(initialState: xdr.isEnabled)
        menu.addItem(toggleItem)

        let sliderItem = NSMenuItem()
        sliderItem.view = makeSliderView(initialLevel: xdr.level)
        menu.addItem(sliderItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit FnSwitchLight",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    func updateTitle() {
        statusItem.button?.title = LayoutManager.currentShortName
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLoginItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginItem.state = .on
            }
        } catch {
            print("⚠️  Failed to toggle launch at login: \(error)")
        }
    }

    @objc private func switchChanged(_ sender: NSSwitch) {
        xdr.setEnabled(sender.state == .on)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        xdr.setLevel(sender.doubleValue)
        xdrValueLabel.stringValue = formattedLevel(xdr.level)
    }

    private func makeToggleView(initialState: Bool) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 32))

        let label = NSTextField(labelWithString: "XDR Boost")
        label.frame = NSRect(x: 14, y: 8, width: 130, height: 16)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        container.addSubview(label)

        let toggle = NSSwitch()
        toggle.state = initialState ? .on : .off
        toggle.target = self
        toggle.action = #selector(switchChanged(_:))
        toggle.frame = NSRect(x: 168, y: 5, width: 40, height: 22)
        container.addSubview(toggle)
        xdrSwitch = toggle

        return container
    }

    private func makeSliderView(initialLevel: Double) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))

        let slider = NSSlider(
            value: initialLevel,
            minValue: XDRBoostController.minLevel,
            maxValue: XDRBoostController.maxLevel,
            target: self,
            action: #selector(sliderChanged(_:))
        )
        slider.isContinuous = true
        slider.frame = NSRect(x: 14, y: 4, width: 150, height: 20)
        container.addSubview(slider)
        xdrSlider = slider

        let label = NSTextField(labelWithString: formattedLevel(initialLevel))
        label.frame = NSRect(x: 170, y: 6, width: 44, height: 16)
        label.font = NSFont.systemFont(ofSize: 11)
        label.alignment = .right
        container.addSubview(label)
        xdrValueLabel = label

        return container
    }

    private func formattedLevel(_ value: Double) -> String {
        String(format: "%.2f×", value)
    }
}
