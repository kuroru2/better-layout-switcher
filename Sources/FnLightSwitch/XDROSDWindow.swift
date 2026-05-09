import Cocoa

/// HUD overlay shown when XDR boost level changes via F1/F2. Sun icon +
/// boost percentage. Matches the look-and-feel of macOS's native brightness
/// OSD that we suppressed by consuming the key event.
final class XDROSDWindow {
    private var window: NSWindow?
    private var icon: NSImageView?
    private var bar: NSView?
    private var hideTimer: Timer?
    private let displayDuration: TimeInterval = 1.0

    /// Show the OSD with the given level (1.0 .. maxLevel). 1.0 = no boost,
    /// `maxLevel` = full boost. The bar fills proportionally to that range.
    func show(level: Double, maxLevel: Double) {
        hideTimer?.invalidate()
        if window == nil { createWindow() }
        guard let window, let bar else { return }

        // Bar fill width — proportional to (level − 1) / (max − 1).
        let progress = max(0, min(1, (level - 1.0) / max(0.0001, maxLevel - 1.0)))
        let barTotalWidth: CGFloat = 184
        if let fill = bar.subviews.first {
            fill.frame.size.width = barTotalWidth * CGFloat(progress)
        }

        // Center on the screen the cursor is currently on.
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens[0]
        let f = window.frame
        window.setFrameOrigin(NSPoint(
            x: screen.frame.midX - f.width / 2,
            y: screen.frame.minY + 140
        ))

        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            window.animator().alphaValue = 1.0
        }

        hideTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    private func hide() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    private func createWindow() {
        let size = NSSize(width: 220, height: 220)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
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

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 18
        bg.layer?.masksToBounds = true
        window.contentView = bg

        let sun = NSImageView(frame: NSRect(x: 70, y: 70, width: 80, height: 80))
        if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 64, weight: .medium)
            sun.image = img.withSymbolConfiguration(cfg)
        }
        sun.contentTintColor = .white
        bg.addSubview(sun)
        self.icon = sun

        // Track-style bar: dim background + bright fill on top.
        let barBG = NSView(frame: NSRect(x: 18, y: 28, width: 184, height: 8))
        barBG.wantsLayer = true
        barBG.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        barBG.layer?.cornerRadius = 4
        bg.addSubview(barBG)

        let fill = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 8))
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor.white.cgColor
        fill.layer?.cornerRadius = 4
        barBG.addSubview(fill)

        self.bar = barBG
        self.window = window
    }
}
