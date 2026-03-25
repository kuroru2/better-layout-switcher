# FnSwitch Project Structure — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the single-file PoC to a proper SPM project with split source files, SwiftLint, and Lefthook pre-commit hooks.

**Architecture:** SPM executable target with 5 source files split by responsibility. FnTapDetector exposes an `onTap` callback; App.swift wires all components. CGEventTap callback is a static method due to C function pointer constraint.

**Tech Stack:** Swift 5.9+, SPM, AppKit, Carbon, SwiftLint, Lefthook

**Spec:** `docs/superpowers/specs/2026-03-25-fnswitch-project-structure-design.md`

**SDK Notes:** On this macOS version, use `.headInsertEventTap` (NOT `.headInsertedEventTap`) and `TISCreateInputSourceList` (NOT `TISCopyInputSourceList`).

---

## File Structure

- **Create:** `Package.swift`
- **Create:** `Sources/FnSwitch/App.swift`
- **Create:** `Sources/FnSwitch/FnTapDetector.swift`
- **Create:** `Sources/FnSwitch/LayoutManager.swift`
- **Create:** `Sources/FnSwitch/OSDWindow.swift`
- **Create:** `Sources/FnSwitch/StatusBarController.swift`
- **Create:** `.swiftlint.yml`
- **Create:** `lefthook.yml`
- **Modify:** `.gitignore`
- **Delete:** `BetterLayoutSwitcher.swift`
- **Delete:** `BetterLayoutSwitcher` (binary)

---

### Task 1: SPM Scaffold + Package.swift

Create the SPM directory structure and Package.swift.

**Files:**
- Create: `Package.swift`
- Create: `Sources/FnSwitch/` (directory)

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p Sources/FnSwitch
```

- [ ] **Step 2: Write Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FnSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FnSwitch",
            path: "Sources/FnSwitch",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Cocoa")
            ]
        )
    ]
)
```

- [ ] **Step 3: Commit**

```bash
git add Package.swift Sources/
git commit -m "chore: add SPM scaffold with Package.swift"
```

---

### Task 2: Split — LayoutManager.swift

Extract TIS input source logic into a static-method-based struct.

**Files:**
- Create: `Sources/FnSwitch/LayoutManager.swift`

- [ ] **Step 1: Write LayoutManager.swift**

```swift
import Carbon

enum LayoutManager {

    static func getKeyboardInputSources() -> [TISInputSource] {
        let conditions: CFDictionary = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsEnabled as String: true as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true as Any
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(conditions, false)?
            .takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return sourceList
    }

    static func shortName(for source: TISInputSource) -> String {
        guard let langs = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return "??"
        }
        // swiftlint:disable:next force_cast
        let languages = Unmanaged<CFArray>.fromOpaque(langs).takeUnretainedValue() as! [String]
        return languages.first?.prefix(2).uppercased() ?? "??"
    }

    static func sourceID(for source: TISInputSource) -> String {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return "unknown"
        }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }

    static var currentShortName: String {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "??"
        }
        return shortName(for: current)
    }

    /// Switches to the next enabled keyboard input source.
    /// Returns the short name of the new layout, or nil if switching failed.
    @discardableResult
    static func switchToNext() -> String? {
        let sources = getKeyboardInputSources()
        if sources.count < 2 {
            print("⚠️  Less than 2 input sources enabled. Nothing to switch.")
            return nil
        }

        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            print("⚠️  Could not get current input source")
            return nil
        }
        let currentID = sourceID(for: current)

        let currentIndex = sources.firstIndex(where: { sourceID(for: $0) == currentID }) ?? 0
        let nextIndex = (currentIndex + 1) % sources.count
        let nextSource = sources[nextIndex]

        let status = TISSelectInputSource(nextSource)
        let name = shortName(for: nextSource)
        if status == noErr {
            return name
        } else {
            print("❌ TISSelectInputSource failed with status: \(status)")
            return nil
        }
    }

    static func printAvailableSources() {
        let sources = getKeyboardInputSources()
        print("📋 Available keyboard layouts:")
        for (i, source) in sources.enumerated() {
            let name = shortName(for: source)
            let id = sourceID(for: source)
            print("   [\(i)] \(name) — \(id)")
        }
        if sources.count < 2 {
            print("⚠️  Need at least 2 input sources for switching!")
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/FnSwitch/LayoutManager.swift
git commit -m "refactor: extract LayoutManager from PoC"
```

---

### Task 3: Split — OSDWindow.swift

Move OSDWindow class as-is.

**Files:**
- Create: `Sources/FnSwitch/OSDWindow.swift`

- [ ] **Step 1: Write OSDWindow.swift**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Sources/FnSwitch/OSDWindow.swift
git commit -m "refactor: extract OSDWindow from PoC"
```

---

### Task 4: Split — StatusBarController.swift

Move StatusBarController, update quit menu text to "Quit FnSwitch", use LayoutManager for current name.

**Files:**
- Create: `Sources/FnSwitch/StatusBarController.swift`

- [ ] **Step 1: Write StatusBarController.swift**

```swift
import Cocoa

class StatusBarController {
    private var statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = LayoutManager.currentShortName
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Quit FnSwitch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    func updateTitle() {
        statusItem.button?.title = LayoutManager.currentShortName
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/FnSwitch/StatusBarController.swift
git commit -m "refactor: extract StatusBarController from PoC"
```

---

### Task 5: Split — FnTapDetector.swift

Extract event tap logic. The CGEventTap callback must be a static method (C function pointer constraint). State is stored as static properties. The class exposes `onTap` callback and `start()` method.

**Files:**
- Create: `Sources/FnSwitch/FnTapDetector.swift`

- [ ] **Step 1: Write FnTapDetector.swift**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Sources/FnSwitch/FnTapDetector.swift
git commit -m "refactor: extract FnTapDetector from PoC"
```

---

### Task 6: Split — App.swift + Remove Old File

Create the entry point that wires everything together. Remove the old PoC file.

**Files:**
- Create: `Sources/FnSwitch/App.swift`
- Delete: `BetterLayoutSwitcher.swift`
- Delete: `BetterLayoutSwitcher` (binary)

- [ ] **Step 1: Write App.swift**

```swift
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    let detector = FnTapDetector()
    let osd = OSDWindow()
    var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()

        detector.onTap = { [self] in
            if let name = LayoutManager.switchToNext() {
                print("Switched to: \(name)")
                osd.show(text: name)
                statusBar.updateTitle()
            }
        }

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
```

- [ ] **Step 2: Remove old PoC files**

```bash
rm -f BetterLayoutSwitcher.swift BetterLayoutSwitcher
```

- [ ] **Step 3: Build with SPM**

```bash
swift build
```

Expected: Build succeeds with no errors.

- [ ] **Step 4: Run and verify**

```bash
.build/debug/FnSwitch
```

Test: App should behave identically to the PoC — Fn tap switches layout, OSD shows, menu bar updates, Quit works.

- [ ] **Step 5: Commit**

```bash
git add Sources/FnSwitch/App.swift
git rm BetterLayoutSwitcher.swift
git commit -m "refactor: complete file split, remove PoC single file"
```

---

### Task 7: SwiftLint Configuration

Add SwiftLint config and fix any lint issues.

**Files:**
- Create: `.swiftlint.yml`

**Prerequisites:** SwiftLint installed (`brew install swiftlint`)

- [ ] **Step 1: Write .swiftlint.yml**

```yaml
excluded:
  - .build
  - Package.swift

disabled_rules:
  - type_body_length
  - trailing_whitespace

line_length:
  warning: 150
  error: 200

file_length:
  warning: 400
  error: 600
```

- [ ] **Step 2: Run SwiftLint and fix any issues**

```bash
swiftlint lint --strict
```

Fix any warnings or errors that appear. Common issues will be around `force_cast` in LayoutManager (the `as! [String]` for TIS API) — add `// swiftlint:disable:next force_cast` inline where needed.

- [ ] **Step 3: Commit**

```bash
git add .swiftlint.yml Sources/
git commit -m "chore: add SwiftLint config and fix lint issues"
```

---

### Task 8: Lefthook + .gitignore

Add Lefthook config and update .gitignore for SPM.

**Files:**
- Create: `lefthook.yml`
- Modify: `.gitignore`

**Prerequisites:** Lefthook installed (`brew install lefthook`)

- [ ] **Step 1: Write lefthook.yml**

```yaml
pre-commit:
  commands:
    swiftlint:
      run: swiftlint lint --strict
    build:
      run: swift build

```

Note: No `pre-push` test hook since there is no test target yet. Add when tests are introduced.

- [ ] **Step 2: Update .gitignore**

Replace the current `.gitignore` with:

```
# SPM
.build/
.swiftpm/
Package.resolved

# Xcode
*.xcodeproj
*.xcworkspace
xcuserdata/
DerivedData/

# macOS
.DS_Store

# Old binaries
FnSwitch
BetterLayoutSwitcher

# Superpowers
.superpowers/
```

- [ ] **Step 3: Install Lefthook hooks**

```bash
lefthook install
```

Expected: Prints confirmation that hooks are installed.

- [ ] **Step 4: Verify pre-commit hook works**

```bash
git add lefthook.yml .gitignore
git commit -m "chore: add Lefthook hooks and update .gitignore"
```

Expected: SwiftLint runs, build runs, both pass, commit succeeds.

---

### Task 9: Final Verification

End-to-end verification that everything works together.

**Files:** None (verification only)

- [ ] **Step 1: Clean build**

```bash
swift package clean
swift build
```

Expected: Clean build succeeds.

- [ ] **Step 2: Run the app**

```bash
.build/debug/FnSwitch
```

Full test checklist:
1. App starts, shows available layouts in console
2. Menu bar shows current layout abbreviation
3. Quick Fn tap → layout switches, OSD shows, menu bar updates
4. Hold Fn + press a key → no switch (modifier use)
5. Hold Fn for >300ms → no switch
6. Click menu bar → "Quit FnSwitch" works

- [ ] **Step 3: Verify SwiftLint passes**

```bash
swiftlint lint --strict
```

Expected: No warnings or errors.

- [ ] **Step 4: Push**

```bash
git push origin main
```
