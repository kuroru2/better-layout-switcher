import Cocoa

/// Intercepts the brightness-up / brightness-down media keys (F1/F2 on Apple
/// keyboards). When `onBrightnessUp`/`onBrightnessDown` returns `true`, the
/// event is consumed (native macOS brightness handling is suppressed). When
/// `false`, the event passes through and macOS adjusts brightness normally.
///
/// Implementation matches Vivid's `repeatBrightnessUp`/`Down` pattern: we let
/// regular brightness work until the user hits SDR max, then take over to
/// step XDR boost instead.
final class XDRKeyTap {
    var onBrightnessUp: (() -> Bool)?
    var onBrightnessDown: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private static var shared: XDRKeyTap?

    func start() {
        XDRKeyTap.shared = self

        // Brightness keys arrive as systemDefined events (NSEvent type 14 /
        // NX_SYSDEFINED), not regular keyDown.
        let mask: CGEventMask = 1 << 14

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: XDRKeyTap.eventCallback,
            userInfo: nil
        ) else {
            print("[XDR] keytap failed to create — accessibility permission missing?")
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, _ in
        // The system can disable our tap on overload — re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = shared?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined else {
            return Unmanaged.passUnretained(event)
        }
        // Aux control buttons (brightness, volume, etc.) come as subtype 8.
        guard nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = (data1 & 0x0000FFFF)
        let keyState = (keyFlags & 0xFF00) >> 8
        let keyDown = (keyState == 0x0A)
        guard keyDown else {
            return Unmanaged.passUnretained(event)
        }
        // NX_KEYTYPE_BRIGHTNESS_UP = 2, BRIGHTNESS_DOWN = 3
        let consumed: Bool
        switch keyCode {
        case 2: consumed = shared?.onBrightnessUp?() ?? false
        case 3: consumed = shared?.onBrightnessDown?() ?? false
        default: return Unmanaged.passUnretained(event)
        }
        if consumed { return nil }
        return Unmanaged.passUnretained(event)
    }
}
