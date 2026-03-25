# Better Layout Switcher PoC — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-file Swift PoC that intercepts Fn taps via CGEventTap, switches keyboard layout via TIS APIs, and shows a centered OSD.

**Architecture:** Single Swift file compiled with `swiftc`. Uses CGEventTap for Fn detection, Carbon TIS APIs for layout switching, and AppKit NSWindow for OSD. Runs as an NSApplication with a menu bar status item.

**Tech Stack:** Swift, AppKit (NSWindow, NSStatusBar), Carbon (TIS APIs), Core Graphics (CGEventTap)

**Spec:** `docs/superpowers/specs/2026-03-25-better-layout-switcher-design.md`

---

## File Structure

- **Create:** `BetterLayoutSwitcher.swift` — single file containing all logic

---

### Task 1: Go/No-Go — Validate Fn Flag Visibility in CGEventTap

The riskiest assumption. Before building anything, confirm that pressing Fn produces a `flagsChanged` event with flag `0x800000` visible to our event tap.

**Files:**
- Create: `BetterLayoutSwitcher.swift`

**Prerequisites:** Set Fn key to "Do Nothing" in System Settings → Keyboard → "Press 🌐 key to"

- [ ] **Step 1: Write minimal event tap that logs all flagsChanged events**

```swift
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
    place: .headInsertedEventTap,
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
```

- [ ] **Step 2: Compile and run**

```bash
cd /Users/sergiiolyva/ctbto/projects/bls
swiftc -framework Cocoa BetterLayoutSwitcher.swift -o BetterLayoutSwitcher
./BetterLayoutSwitcher
```

Expected: Program starts, prints "Event tap created. Press Fn key to test..."

- [ ] **Step 3: Test Fn key — press and release Fn**

Press Fn key once. Watch console output.

**GO outcome:** You see two lines:
```
flagsChanged: raw flags = 0x8XXXXX
  ✅ Fn flag IS SET
flagsChanged: raw flags = 0xXXXXXX
  ❌ Fn flag is NOT set
```

**NO-GO outcome:** Nothing prints when pressing Fn, or Fn flag never appears. → **STOP execution.** Return to the user for re-planning. Fallback options are IOHIDManager or NSEvent global monitor (see spec Risk section).

- [ ] **Step 4: If GO — commit the skeleton**

```bash
git add BetterLayoutSwitcher.swift
git commit -m "feat: validate Fn flag visibility via CGEventTap"
```

---

### Task 2: Fn Tap Detection (Tap vs Modifier)

Add logic to distinguish a short Fn tap from Fn used as a modifier (Fn+F1, etc.).

**Files:**
- Modify: `BetterLayoutSwitcher.swift`

- [ ] **Step 1: Replace entire file with tap detection version**

This is a **full file replacement** of `BetterLayoutSwitcher.swift`. Each subsequent task also provides the complete file content to avoid ambiguity about patches vs replacements.

```swift
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
    place: .headInsertedEventTap,
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
```

- [ ] **Step 2: Compile and test**

```bash
cd /Users/sergiiolyva/ctbto/projects/bls
swiftc -framework Cocoa BetterLayoutSwitcher.swift -o BetterLayoutSwitcher
./BetterLayoutSwitcher
```

Test these scenarios:
1. Quick Fn tap → should print "Fn TAP detected"
2. Hold Fn for 1 second → should print "Fn modifier use — ignoring"
3. Hold Fn + press F1 → should print key event + "Fn modifier use — ignoring"

- [ ] **Step 3: Commit**

```bash
git add BetterLayoutSwitcher.swift
git commit -m "feat: add Fn tap vs modifier detection with timing"
```

---

### Task 3: Layout Switching via TIS APIs

Add layout switching that triggers on Fn tap. Uses Carbon TIS APIs to enumerate input sources and toggle between the first two.

**Files:**
- Modify: `BetterLayoutSwitcher.swift`

- [ ] **Step 1: Add layout switching functions**

**Full file replacement.** Add these functions before the event callback. Add `import Carbon` at the top alongside `import Cocoa`:

```swift
import Carbon

func getKeyboardInputSources() -> [TISInputSource] {
    let conditions: CFDictionary = [
        kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
        kTISPropertyInputSourceIsEnabled as String: true as Any,
        kTISPropertyInputSourceIsSelectCapable as String: true as Any
    ] as CFDictionary

    guard let sourceList = TISCopyInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource] else {
        return []
    }
    return sourceList
}

func getInputSourceShortName(_ source: TISInputSource) -> String {
    guard let langs = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
        return "??"
    }
    let languages = Unmanaged<CFArray>.fromOpaque(langs).takeUnretainedValue() as! [String]
    return languages.first?.prefix(2).uppercased() ?? "??"
}

func getInputSourceID(_ source: TISInputSource) -> String {
    guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
        return "unknown"
    }
    return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
}

func switchToNextLayout() {
    let sources = getKeyboardInputSources()
    if sources.count < 2 {
        print("⚠️  Less than 2 input sources enabled. Nothing to switch.")
        return
    }

    guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
        print("⚠️  Could not get current input source")
        return
    }
    let currentID = getInputSourceID(current)

    // Find current index, switch to the other one
    let currentIndex = sources.firstIndex(where: { getInputSourceID($0) == currentID }) ?? 0
    let nextIndex = (currentIndex + 1) % sources.count
    let nextSource = sources[nextIndex]

    let status = TISSelectInputSource(nextSource)
    let name = getInputSourceShortName(nextSource)
    if status == noErr {
        print("🔄 Switched to: \(name) (\(getInputSourceID(nextSource)))")
    } else {
        print("❌ TISSelectInputSource failed with status: \(status)")
    }
}
```

- [ ] **Step 2: Wire tap detection to layout switching**

In the event callback, replace the "would switch layout here" print with an actual call. All TIS and NSWindow operations must happen on the main thread:

```swift
// Replace:
//   print("✅ Fn TAP detected — would switch layout here")
// With:
print("✅ Fn TAP detected")
DispatchQueue.main.async {
    switchToNextLayout()
}
```

Note: `switchToNextLayout()` is always called via `DispatchQueue.main.async` from the callback. All UI operations (OSD, status bar updates added in later tasks) happen inside `switchToNextLayout()` and are therefore guaranteed to be on the main thread.

- [ ] **Step 3: Print available layouts at startup**

Add after the event tap setup, before `CFRunLoopRun()`:

```swift
let sources = getKeyboardInputSources()
print("📋 Available keyboard layouts:")
for (i, source) in sources.enumerated() {
    let name = getInputSourceShortName(source)
    let id = getInputSourceID(source)
    print("   [\(i)] \(name) — \(id)")
}
if sources.count < 2 {
    print("⚠️  Need at least 2 input sources for switching!")
}
```

- [ ] **Step 4: Switch to NSApplication run loop**

CGEventTap needs a run loop, and later we need NSApplication for windows. Replace `CFRunLoopRun()` with NSApplication. Add before the run loop setup:

```swift
let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // No dock icon

// ... existing run loop source setup ...

app.run()  // Replace CFRunLoopRun()
```

- [ ] **Step 5: Compile and test**

```bash
cd /Users/sergiiolyva/ctbto/projects/bls
swiftc -framework Cocoa -framework Carbon BetterLayoutSwitcher.swift -o BetterLayoutSwitcher
./BetterLayoutSwitcher
```

Test: Quick Fn tap should print layout list at start, then switch layout on tap. Verify in menu bar that the layout actually changed.

- [ ] **Step 6: Commit**

```bash
git add BetterLayoutSwitcher.swift
git commit -m "feat: add layout switching via TIS APIs on Fn tap"
```

---

### Task 4: OSD Window

Add a borderless overlay window that shows the layout name centered on screen for 1 second with fade in/out.

**Files:**
- Modify: `BetterLayoutSwitcher.swift`

- [ ] **Step 1: Add OSD window class**

Add this class before the event callback:

```swift
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
```

- [ ] **Step 2: Wire OSD to layout switching**

Add a global OSD instance and update `switchToNextLayout()` to show OSD:

```swift
let osd = OSDWindow()

// In switchToNextLayout(), after successful TISSelectInputSource:
// Add:
osd.show(text: name)
```

- [ ] **Step 3: Compile and test**

```bash
cd /Users/sergiiolyva/ctbto/projects/bls
swiftc -framework Cocoa -framework Carbon BetterLayoutSwitcher.swift -o BetterLayoutSwitcher
./BetterLayoutSwitcher
```

Test: Fn tap should show a dark rounded rectangle with "EN" or "UA" (etc.) centered on screen for 1 second, then fade out.

- [ ] **Step 4: Commit**

```bash
git add BetterLayoutSwitcher.swift
git commit -m "feat: add OSD overlay window showing layout name"
```

---

### Task 5: Menu Bar Status Item

Add a menu bar icon showing the current layout abbreviation with a Quit menu item.

**Files:**
- Modify: `BetterLayoutSwitcher.swift`

- [ ] **Step 1: Add StatusBarController**

Add this class:

```swift
class StatusBarController {
    private var statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = currentLayoutShortName()
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Better Layout Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateTitle() {
        statusItem.button?.title = currentLayoutShortName()
    }
}

func currentLayoutShortName() -> String {
    guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
        return "??"
    }
    return getInputSourceShortName(current)
}
```

- [ ] **Step 2: Create status bar and wire to switching**

Add a global status bar instance after the OSD instance:

```swift
var statusBar: StatusBarController!
```

Initialize it after `app.setActivationPolicy(.accessory)`:

```swift
statusBar = StatusBarController()
```

Update `switchToNextLayout()` to also update the status bar after switching:

```swift
statusBar.updateTitle()
```

- [ ] **Step 3: Compile and test**

```bash
cd /Users/sergiiolyva/ctbto/projects/bls
swiftc -framework Cocoa -framework Carbon BetterLayoutSwitcher.swift -o BetterLayoutSwitcher
./BetterLayoutSwitcher
```

Test:
1. Menu bar should show current layout abbreviation (e.g., "EN")
2. Fn tap should switch layout, update menu bar title, and show OSD
3. Click menu bar item → "Quit Better Layout Switcher" should exit the app

- [ ] **Step 4: Commit**

```bash
git add BetterLayoutSwitcher.swift
git commit -m "feat: add menu bar status item with current layout and quit"
```

---

### Task 6: Final Integration & Cleanup

Clean up debug logging, ensure everything works together, add a .gitignore.

**Files:**
- Modify: `BetterLayoutSwitcher.swift`
- Create: `.gitignore`

- [ ] **Step 1: Add .gitignore**

```
# Build artifacts
BetterLayoutSwitcher
*.o
*.swp

# macOS
.DS_Store

# Superpowers
.superpowers/
```

- [ ] **Step 2: Reduce console noise**

Keep essential logging but reduce verbosity. Remove the raw flags hex dump. Keep:
- Startup: available layouts, event tap status
- Fn tap: "Switched to: EN" (one line per switch)
- Errors: any failures

- [ ] **Step 3: Final compile and end-to-end test**

```bash
cd /Users/sergiiolyva/ctbto/projects/bls
swiftc -framework Cocoa -framework Carbon BetterLayoutSwitcher.swift -o BetterLayoutSwitcher
./BetterLayoutSwitcher
```

Full test checklist:
1. App starts, shows available layouts in console
2. Menu bar shows current layout abbreviation
3. Quick Fn tap → layout switches, OSD shows, menu bar updates
4. Hold Fn + press F1 → no switch (modifier use)
5. Hold Fn for >300ms → no switch
6. Rapid double-tap Fn → switches twice
7. Click menu bar → Quit works

- [ ] **Step 4: Commit and push**

```bash
git add .gitignore BetterLayoutSwitcher.swift
git commit -m "feat: complete PoC — Fn tap layout switcher with OSD"
git push -u origin main
```
