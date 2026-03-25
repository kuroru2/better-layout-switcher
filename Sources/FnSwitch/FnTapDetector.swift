import Cocoa

class FnTapDetector {

    var onTap: (() -> Void)?

    // --- Static state for C callback ---
    private static var previousFlags: UInt64 = 0
    private static var fnDownTimestamp: UInt64 = 0
    private static var fnIsDown = false
    private static var otherKeyPressed = false
    private static let fnFlag: UInt64 = 0x800000
    private static let tapThresholdMs: Double = 300.0
    private static var globalEventTap: CFMachPort?

    // Shared instance so static callback can reach onTap
    private static var shared: FnTapDetector?

    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func machToMs(_ elapsed: UInt64) -> Double {
        let nanos = elapsed * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        return Double(nanos) / 1_000_000.0
    }

    // --- Public API ---

    func start() {
        FnTapDetector.shared = self

        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: FnTapDetector.eventCallback,
            userInfo: nil
        ) else {
            print("❌ Failed to create event tap. Grant Accessibility permission.")
            print("   System Settings → Privacy & Security → Accessibility")
            exit(1)
        }

        FnTapDetector.globalEventTap = eventTap

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        print("✅ FnSwitch running (tap threshold: \(FnTapDetector.tapThresholdMs)ms)")
    }

    // --- C-compatible static callback ---

    private static let eventCallback: CGEventTapCallBack = { _, type, event, _ in

        // Handle event tap being disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("⚠️  Event tap disabled, re-enabling...")
            if let tap = globalEventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let currentFlags = event.flags.rawValue

        if type == .flagsChanged {
            let fnNowSet = (currentFlags & fnFlag) != 0
            let fnWasSet = (previousFlags & fnFlag) != 0

            if fnNowSet && !fnWasSet {
                // Fn pressed
                fnIsDown = true
                otherKeyPressed = false
                fnDownTimestamp = mach_absolute_time()
            } else if !fnNowSet && fnWasSet {
                // Fn released
                let elapsed = machToMs(mach_absolute_time() - fnDownTimestamp)

                if elapsed < tapThresholdMs && !otherKeyPressed {
                    DispatchQueue.main.async {
                        shared?.onTap?()
                    }
                    // Suppress the Fn release event
                    fnIsDown = false
                    otherKeyPressed = false
                    previousFlags = currentFlags
                    return nil
                }
                fnIsDown = false
                otherKeyPressed = false
            }
            previousFlags = currentFlags

        } else if type == .keyDown || type == .keyUp {
            if fnIsDown {
                otherKeyPressed = true
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
