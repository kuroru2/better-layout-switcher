import Cocoa

// --- Timing helper ---
// Cache timebase info to avoid repeated syscalls
let timebaseInfo: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
}()

func machToMs(_ elapsed: UInt64) -> Double {
    let nanos = elapsed * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
    return Double(nanos) / 1_000_000.0
}

// --- State ---
var previousFlags: UInt64 = 0
var fnDownTimestamp: UInt64 = 0
var fnIsDown = false
var otherKeyPressed = false
let fnFlag: UInt64 = 0x800000
let tapThresholdMs: Double = 300.0

// Global reference to event tap for re-enabling on timeout
var globalEventTap: CFMachPort?

func eventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

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
            print("🔽 Fn DOWN")
        } else if !fnNowSet && fnWasSet {
            // Fn released
            let elapsed = machToMs(mach_absolute_time() - fnDownTimestamp)
            print("🔼 Fn UP (held \(String(format: "%.0f", elapsed))ms, otherKey: \(otherKeyPressed))")

            if elapsed < tapThresholdMs && !otherKeyPressed {
                print("✅ Fn TAP detected — would switch layout here")
                // Suppress the Fn release event so macOS doesn't act on it
                fnIsDown = false
                otherKeyPressed = false
                previousFlags = currentFlags
                return nil
            } else {
                print("⏭️  Fn modifier use — ignoring")
            }
            fnIsDown = false
            otherKeyPressed = false
        }
        previousFlags = currentFlags

    } else if type == .keyDown || type == .keyUp {
        if fnIsDown {
            otherKeyPressed = true
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            print("⌨️  Key \(type == .keyDown ? "down" : "up") (code: \(keyCode)) while Fn held")
        }
    }

    return Unmanaged.passUnretained(event)
}

// --- Setup ---
let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
    | (1 << CGEventType.keyDown.rawValue)
    | (1 << CGEventType.keyUp.rawValue)

guard let eventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: eventCallback,
    userInfo: nil
) else {
    print("❌ Failed to create event tap. Grant Accessibility permission.")
    exit(1)
}

globalEventTap = eventTap

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)

print("✅ Fn tap detector running (threshold: \(tapThresholdMs)ms)")
print("   Press Fn quickly = tap | Hold Fn + other key = modifier")
print("   Ctrl+C to quit")

CFRunLoopRun()
