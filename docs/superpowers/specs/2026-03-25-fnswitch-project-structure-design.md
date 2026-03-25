# FnSwitch Project Structure — Design Spec

## Problem

The PoC is a single-file Swift app compiled with `swiftc`. It works but has no project structure, no linting, no pre-commit hooks, and no test infrastructure. Time to make it a proper project.

## Solution

Migrate the PoC to a Swift Package Manager project with split source files, SwiftLint, Lefthook pre-commit hooks, and a test target.

## Scope

### Delivers

1. **SPM project** — `Package.swift` with executable target and test target
2. **File split** — 5 focused source files from the single PoC file
3. **SwiftLint** — linter config with sensible defaults
4. **Lefthook** — pre-commit hooks (SwiftLint + build), pre-push hooks (tests)
5. **Updated .gitignore** — SPM build artifacts, Xcode artifacts
6. **Rename** — BetterLayoutSwitcher → FnSwitch, bundle ID `com.kuroru2.fnswitch`

### Does NOT Deliver

- New features (OSD position, settings UI, launch at login, etc.)
- Changes to app behavior — the app works identically after migration (the wiring refactor is structural, not behavioral)
- Xcode project generation (SPM can open directly in Xcode via `open Package.swift`)

## Architecture

### File Structure

```
FnSwitch/
├── Package.swift
├── Sources/
│   └── FnSwitch/
│       ├── App.swift
│       ├── FnTapDetector.swift
│       ├── LayoutManager.swift
│       ├── OSDWindow.swift
│       └── StatusBarController.swift
├── .swiftlint.yml
├── lefthook.yml
├── .gitignore
└── docs/                          # Existing specs/plans (unchanged)
```

### File Responsibilities

| File | Responsibility | Depends On |
|------|---------------|-----------|
| `App.swift` | Entry point (top-level code), NSApplication setup, AppDelegate, wires components | All others |
| `FnTapDetector.swift` | CGEventTap lifecycle, Fn flag tracking, tap-vs-modifier timing. Includes `machToMs()` timing helper and cached `timebaseInfo`. The `eventCallback` is a static method (required by C function pointer constraint). | Foundation only |
| `LayoutManager.swift` | TIS APIs: enumerate sources, switch, get current name/ID. Absorbs `getKeyboardInputSources()`, `getInputSourceShortName()`, `getInputSourceID()`, `currentLayoutShortName()` as static methods. | Carbon |
| `OSDWindow.swift` | Borderless NSWindow overlay, show/hide with fade animation | AppKit |
| `StatusBarController.swift` | NSStatusItem, menu with Quit ("Quit FnSwitch"), display current layout | AppKit |

### Component Coupling

`FnTapDetector` does not depend on `LayoutManager`. It exposes a callback:

```swift
class FnTapDetector {
    var onTap: (() -> Void)?
    func start() { ... }
}
```

`App.swift` is the single file with top-level code (SPM allows exactly one per executable target). It sets up NSApplication, creates an AppDelegate, and wires components in `applicationDidFinishLaunching`:

```swift
// App.swift (top-level code)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// AppDelegate wires components
class AppDelegate: NSObject, NSApplicationDelegate {
    let detector = FnTapDetector()
    let osd = OSDWindow()
    var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        detector.onTap = { [self] in
            LayoutManager.switchToNext()
            osd.show(text: LayoutManager.currentShortName)
            statusBar.updateTitle()
        }
        detector.start()
    }
}
```

### CGEventTap Callback Constraint

`CGEvent.tapCreate` requires a C function pointer — it cannot be a closure or instance method. The event callback must be a free function or `static` method on `FnTapDetector`. The static method approach keeps it co-located with the state it accesses. `FnTapDetector` uses static/global state for the callback, with instance methods for the public API.

### Package.swift

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

Note: No test target for now. Testing an executable that relies on CGEventTap and TIS system APIs is not meaningful without protocol abstractions. We'll add a test target when we introduce testable pure logic (e.g., configuration parsing). The placeholder `Tests/` directory is omitted to avoid a broken test target.

## Tooling

### SwiftLint (`.swiftlint.yml`)

Sensible defaults. Key decisions:
- Disable `type_body_length` — OSDWindow has a large `createWindow()` method, acceptable for now
- Disable `line_length` warning above 150 chars (not 120) — long TIS API names
- Warn on `force_cast` (used in TIS Unmanaged bridging — acceptable in this context)
- Exclude `.build/` and `Tests/` from strict rules

### Lefthook (`lefthook.yml`)

```yaml
pre-commit:
  commands:
    swiftlint:
      run: swiftlint lint --strict
    build:
      run: swift build

pre-push:
  commands:
    test:
      run: swift test
```

### .gitignore

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

## Migration Steps (High Level)

1. Create SPM project structure (Package.swift, directories)
2. Split `BetterLayoutSwitcher.swift` into 5 files
3. Remove old `BetterLayoutSwitcher.swift` and binary
4. Verify `swift build` compiles
5. Verify app runs identically
6. Add SwiftLint config, fix any lint issues
7. Add Lefthook config, install hooks
8. Update .gitignore

## Prerequisites

- SwiftLint installed (`brew install swiftlint`)
- Lefthook installed (`brew install lefthook`)

## Build & Run

```bash
swift build
.build/debug/FnSwitch
```

Or open in Xcode: `open Package.swift`
