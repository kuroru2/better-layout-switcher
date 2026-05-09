import Cocoa
import CoreGraphics

/// XDR Boost: pushes the panel past the SDR brightness cap on EDR-capable
/// displays. The mechanism is two cooperating pieces (same shape Vivid uses):
///
/// 1. **HDR pin** — `XDRPinWindow` plays a tiny HDR-tagged video on each
///    display. Real HDR video playback is what puts the panel into HDR mode,
///    which is the hardware capability gate — without HDR mode active, the
///    panel refuses to drive brightness past SDR cap regardless of any
///    software input.
/// 2. **Gamma-table boost** — once HDR mode is active, multiplying the per-
///    channel gamma table (256 floats × 3 channels) by the boost factor and
///    writing it back via `CGSetDisplayTransferByTable` makes the panel
///    actually output brighter pixels for every framebuffer value. This is
///    public CoreGraphics, no private API needed. The Formula version of the
///    same call rejects values > 1.0 with kCGErrorRangeCheck; the Table
///    version doesn't validate, so on EDR displays > 1.0 entries pass through.
///
/// Disable / app exit / crash → `CGDisplayRestoreColorSyncSettings()` reverts
/// gamma to the system default.
final class XDRBoostController {
    static let minLevel: Double = 1.0
    static let maxLevel: Double = 2.0
    static let defaultLevel: Double = 1.3

    /// Set on launch by the AppDelegate; used by AppIntent / Shortcuts
    /// integration in `XDRBoostIntents.swift` to reach the live controller.
    static weak var shared: XDRBoostController?

    /// On-screen indicator shown when boost steps via F1/F2.
    var osd: XDROSDWindow?

    /// Step size used by F1/F2 / Shortcuts increase-decrease intents.
    static let stepSize: Double = 0.1

    /// Threshold for "user is at max system brightness" — at or above this,
    /// pressing brightness-up takes over and steps XDR boost instead.
    private static let maxSystemBrightnessThreshold: Float = 0.999

    private static let enabledKey = "xdrBoostEnabled"
    private static let levelKey = "xdrBoostLevel"

    private struct BaselineGamma {
        let red: [CGGammaValue]
        let green: [CGGammaValue]
        let blue: [CGGammaValue]
        let sampleCount: UInt32
    }

    private var pins: [CGDirectDisplayID: XDRPinWindow] = [:]
    private var baselineGammas: [CGDirectDisplayID: BaselineGamma] = [:]
    private var lastReconciledDisplayIDs: Set<CGDirectDisplayID> = []

    private(set) var isEnabled: Bool
    private(set) var level: Double

    init() {
        // Clear any leftover gamma-table modifications from a prior process
        // that exited without restoring (Ctrl-C, crash, etc.) — without this
        // we read a partially-modified gamma as our "baseline" and the boost
        // compounds across runs.
        CGDisplayRestoreColorSyncSettings()

        let defaults = UserDefaults.standard
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        let storedLevel = defaults.double(forKey: Self.levelKey)
        self.level = storedLevel == 0.0
            ? Self.defaultLevel
            : storedLevel.clamped(to: Self.minLevel ... Self.maxLevel)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Defensive: revert any gamma modifications on app exit so a crash
        // can't leave the user staring at a permanently-altered display.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restoreOnExit),
            name: NSApplication.willTerminateNotification,
            object: nil
        )

        if isEnabled {
            startAll()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func restoreOnExit() {
        CGDisplayRestoreColorSyncSettings()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            startAll()
        } else {
            stopAll()
        }
    }

    func setLevel(_ newLevel: Double) {
        let clamped = newLevel.clamped(to: Self.minLevel ... Self.maxLevel)
        guard clamped != level else { return }
        level = clamped
        UserDefaults.standard.set(clamped, forKey: Self.levelKey)
        if isEnabled {
            for id in pins.keys { applyGammaBoost(displayID: id, factor: Float(level)) }
        }
    }

    /// Called by `XDRKeyTap` when user presses brightness-up. Returns
    /// `true` if we consumed the event (we stepped boost instead of letting
    /// macOS do its native brightness adjustment), `false` otherwise.
    @discardableResult
    func handleBrightnessUpKey() -> Bool {
        // Gate: only take over when boost is enabled AND user is already at
        // max system brightness — matches Vivid's UX exactly. Below max, we
        // let the native system handle the key.
        guard isEnabled, isUserAtMaxBrightness() else { return false }
        guard level < Self.maxLevel else {
            // Already at max — show OSD anyway to give feedback, consume.
            osd?.show(level: level, maxLevel: Self.maxLevel)
            return true
        }
        setLevel(level + Self.stepSize)
        osd?.show(level: level, maxLevel: Self.maxLevel)
        return true
    }

    /// Symmetric to handleBrightnessUpKey: only steps boost down if we're
    /// already in boosted territory (level > 1.0). At level 1.0 we let the
    /// native system handle the key (user wants to dim system brightness).
    @discardableResult
    func handleBrightnessDownKey() -> Bool {
        guard isEnabled, level > Self.minLevel else { return false }
        setLevel(level - Self.stepSize)
        osd?.show(level: level, maxLevel: Self.maxLevel)
        return true
    }

    private func isUserAtMaxBrightness() -> Bool {
        // Any display being at max counts as "at max". On a single-display
        // setup this is just the main display.
        for screen in NSScreen.screens {
            guard let id = displayID(of: screen) else { continue }
            var br: Float = 0
            _ = displayServicesGetBrightness(id, &br)
            if br >= Self.maxSystemBrightnessThreshold { return true }
        }
        return false
    }

    /// Multiply the cached *baseline* gamma table by `factor` and write it
    /// back. Always multiplies baseline, never the current (already-modified)
    /// table — otherwise factor changes compound and the screen runs away.
    private func applyGammaBoost(displayID id: CGDirectDisplayID, factor: Float) {
        if baselineGammas[id] == nil {
            // Reset before reading so we capture the OS default, not a
            // stale modification from a prior process.
            CGDisplayRestoreColorSyncSettings()
            let capacity: UInt32 = 256
            var red = [CGGammaValue](repeating: 0, count: Int(capacity))
            var green = [CGGammaValue](repeating: 0, count: Int(capacity))
            var blue = [CGGammaValue](repeating: 0, count: Int(capacity))
            var sampleCount: UInt32 = 0
            let getErr = CGGetDisplayTransferByTable(id, capacity, &red, &green, &blue, &sampleCount)
            guard getErr == .success, sampleCount > 0 else {
                print("[XDR] CGGetDisplayTransferByTable failed: \(getErr.rawValue)")
                return
            }
            let used = Int(sampleCount)
            baselineGammas[id] = BaselineGamma(
                red: Array(red.prefix(used)),
                green: Array(green.prefix(used)),
                blue: Array(blue.prefix(used)),
                sampleCount: sampleCount
            )
        }
        guard let base = baselineGammas[id] else { return }

        var red = base.red.map { $0 * factor }
        var green = base.green.map { $0 * factor }
        var blue = base.blue.map { $0 * factor }
        let setErr = CGSetDisplayTransferByTable(id, base.sampleCount, &red, &green, &blue)
        if setErr != .success {
            print("[XDR] CGSetDisplayTransferByTable failed: \(setErr.rawValue)")
        }
    }

    @objc private func screensChanged() {
        guard isEnabled else { return }
        let currentIDs = Set(NSScreen.screens.compactMap(displayID(of:)))
        if currentIDs == lastReconciledDisplayIDs { return }
        startAll()
    }

    private func startAll() {
        guard let url = Bundle.main.url(forResource: "hdr", withExtension: "mov") else {
            print("[XDR] hdr.mov resource not found in bundle")
            return
        }
        reconcilePins(videoURL: url)
    }

    private func reconcilePins(videoURL: URL) {
        let nsScreens = NSScreen.screens
        let currentIDs: Set<CGDirectDisplayID> = Set(nsScreens.compactMap(displayID(of:)))
        lastReconciledDisplayIDs = currentIDs

        for id in pins.keys where !currentIDs.contains(id) {
            pins[id]?.stop()
            pins[id]?.orderOut(nil)
            pins.removeValue(forKey: id)
        }

        for screen in nsScreens {
            guard let id = displayID(of: screen) else { continue }
            if pins[id] != nil { continue }

            let window = XDRPinWindow(screen: screen, hdrVideoURL: videoURL)
            window.orderFrontRegardless()
            pins[id] = window

            // Wait for HDR mode to commit before applying the gamma boost.
            // Without HDR mode, gamma values > 1.0 just become an SDR curve
            // manipulation (washed darks, no real nit gain).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                let h = screen.maximumExtendedDynamicRangeColorComponentValue
                print("[XDR] EDR headroom display=\(id) current=\(h) — HDR mode \(h > 1.0 ? "ACTIVE" : "NOT active")")
                self.applyGammaBoost(displayID: id, factor: Float(self.level))
            }
            // Sample headroom 4s and 8s after start — by then the pin's
            // AVPlayer has paused (at ~2s). If HDR mode stays > 1.0 in these
            // later samples, pause-after-commit works and we can ship near-
            // zero CPU. If headroom drops back to 1.0, HDR died on pause.
            for delay in [4.0, 8.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let h = screen.maximumExtendedDynamicRangeColorComponentValue
                    print("[XDR] post-pause headroom @ \(delay)s: \(h)")
                }
            }
        }
    }

    private func stopAll() {
        for pin in pins.values {
            pin.stop()
            pin.orderOut(nil)
        }
        pins.removeAll()
        lastReconciledDisplayIDs = []
        baselineGammas.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
