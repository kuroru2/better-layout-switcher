import Cocoa

class OSDWindow {
    private var window: NSWindow?
    private var hideTimer: Timer?
    private let displayDuration: TimeInterval = 1.0

    func show(text: String) {
        hideTimer?.invalidate()

        if window == nil {
            createWindow()
        }

        guard let window = window,
              let label = window.contentView?.subviews.first as? NSTextField else { return }

        label.stringValue = text

        // Center on screen with mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens[0]

        let screenFrame = screen.frame
        let windowSize = window.frame.size
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.midY - windowSize.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))

        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 1.0
        }

        hideTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    private func hide() {
        guard let window = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    private func createWindow() {
        let windowSize = NSSize(width: 120, height: 80)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Rounded dark background
        let bgView = NSVisualEffectView(frame: NSRect(origin: .zero, size: windowSize))
        bgView.material = .hudWindow
        bgView.state = .active
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 16
        bgView.layer?.masksToBounds = true
        window.contentView = bgView

        // Label
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 32, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        bgView.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: bgView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: bgView.centerYAnchor),
            label.widthAnchor.constraint(equalTo: bgView.widthAnchor, constant: -16)
        ])

        self.window = window
    }
}
