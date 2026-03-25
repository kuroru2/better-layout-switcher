import Cocoa

// Minimal CGEventTap to log flagsChanged events and their raw flags
func eventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .flagsChanged {
        let flags = event.flags.rawValue
        print("flagsChanged: raw flags = 0x\(String(flags, radix: 16))")

        let fnFlag: UInt64 = 0x800000
        if flags & fnFlag != 0 {
            print("  ✅ Fn flag IS SET")
        } else {
            print("  ❌ Fn flag is NOT set")
        }
    }
    return Unmanaged.passUnretained(event)
}

// Create event tap for flagsChanged + keyDown + keyUp
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
    print("❌ Failed to create event tap. Grant Accessibility permission:")
    print("   System Settings → Privacy & Security → Accessibility")
    print("   Add Terminal (or iTerm2) to the list")
    exit(1)
}

print("✅ Event tap created. Press Fn key to test...")
print("   (Press Ctrl+C to quit)")

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)
CFRunLoopRun()
