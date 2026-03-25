# Better Layout Switcher — Design Spec

## Problem

macOS keyboard layout switching via the Fn key is unreliable on macOS 15.3. The key often requires multiple presses to register, and the system OSD is inconsistent — sometimes appearing near the cursor, sometimes as an OSD, sometimes only in the menu bar tray.

## Solution

A native macOS menu bar app that intercepts Fn key taps at the system level via CGEventTap, performs layout switching itself via TIS APIs, and shows a consistent, always-visible OSD.

## Scope: Proof of Concept

The PoC is a single Swift file that validates the riskiest assumption: **can we reliably detect Fn taps via CGEventTap and distinguish them from Fn-as-modifier usage?**

### PoC Delivers

1. **Fn tap detection** — CGEventTap listening for `.flagsChanged`, tracking Fn flag transitions, distinguishing tap (press+release <300ms, no other keys) from modifier use (Fn+F1, etc.)
2. **Layout switching** — `TISSelectInputSource()` to toggle between the first two enabled input sources
3. **OSD** — borderless, always-on-top NSWindow centered on screen, showing layout short name (e.g. "EN"), auto-hides after 1 second
4. **Console logging** — debug output showing Fn events, timing, and switching decisions

### PoC Does NOT Deliver

- Settings UI (tap duration, OSD duration are hardcoded)
- Configurable OSD position (centered only)
- Launch at login
- Multiple layout cycling (toggle between first two only)
- Persistence of preferences

## Architecture

### Approach: CGEventTap

Selected over IOHIDManager (too complex for the need) and NSEvent global monitor (cannot suppress events — macOS would still process Fn).

CGEventTap allows us to:
- Intercept Fn key-down/key-up at the HID level
- Suppress the tap event so macOS doesn't also try to switch layouts
- Pass through Fn+key combos untouched

Requires Accessibility permission (one-time grant in System Settings → Privacy & Security → Accessibility).

### Fn Tap Detection Logic

Note: `flagsChanged` events deliver a new flags mask, not discrete key-down/key-up. We diff the previous mask against the current one to infer Fn press/release. Timing uses `mach_absolute_time()` converted to milliseconds.

```
flagsChanged event received:
  → compare current flags with previous flags
  → if Fn flag (0x800000) is NOW SET (was not before):
      → record timestamp (mach_absolute_time)
      → set fnIsDown = true
  → if Fn flag is NOW CLEARED (was set before):
      → elapsed = (now - timestamp) converted to ms
      → if elapsed < 300ms AND !otherKeyPressed:
          → it's a tap → dispatch to main thread: switch layout, show OSD
      → else:
          → it's a modifier use → do nothing
      → reset state (fnIsDown = false, otherKeyPressed = false)

Any keyDown/keyUp event while fnIsDown:
  → set otherKeyPressed = true
  → pass through (Fn is being used as modifier)
```

Threading: CGEventTap callback fires on the run loop thread. `TISSelectInputSource()` and NSWindow operations must be dispatched to the main thread via `DispatchQueue.main.async`.

### Layout Switching

- `TISCopyInputSourceList()` with `kTISPropertyInputSourceIsEnabled` and `kTISPropertyInputSourceCategory == kTISCategoryKeyboardInputSource` to get available keyboard layouts
- Layout short name: use `kTISPropertyInputSourceLanguages` (first element, uppercased) — e.g., "EN", "UK"
- Track current layout index, advance to next on tap (for PoC: toggle between first two)
- If fewer than 2 input sources are enabled, log a warning and do nothing on tap
- `TISSelectInputSource()` to activate

### OSD Window

- `NSWindow` with `styleMask: .borderless`, `level: .screenSaver` (above everything)
- `backgroundColor: .clear` with a rounded dark/semi-transparent backing view
- White text label showing layout short name
- Fade in, hold 1 second, fade out
- Centered on the screen containing the mouse cursor

### Menu Bar

- `NSStatusBar.system.statusItem` showing current layout abbreviation
- Simple menu with "Quit" item

## Project Structure (PoC)

```
BetterLayoutSwitcher/
├── BetterLayoutSwitcher.swift   # Single file PoC
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-03-25-better-layout-switcher-design.md
```

## Prerequisites

- macOS 15.0+ (Apple Silicon) — developed and tested on 15.3
- Fn key set to "Do Nothing" in System Settings → Keyboard (so macOS doesn't compete for the Fn tap; our app handles switching exclusively)
- Accessibility permission granted to the compiled binary / Terminal

## Build & Run (PoC)

```bash
swiftc -framework Cocoa -framework Carbon BetterLayoutSwitcher.swift -o BetterLayoutSwitcher
./BetterLayoutSwitcher
```

## Future (Post-PoC)

- Full app structure (XcodeGen, following tunnel-master pattern)
- Menu bar icon with settings dropdown
- Configurable tap duration (default 300ms)
- Configurable OSD duration (default 1s)
- OSD near mouse cursor / text caret (via Accessibility API)
- Multiple layout cycling (3+ layouts)
- Launch at login
- Language flags/icons in OSD

## Risk

The primary risk is whether CGEventTap reliably receives Fn flag change events on macOS 15.3. On Apple Silicon, the Fn key may be consumed by firmware/driver before reaching the event tap layer, especially when set to "Change Input Source." Setting Fn to "Do Nothing" should let the flag events through, but this needs validation.

**Go/no-go checkpoint:** Before building tap detection logic, the PoC's first step is to log raw `flagsChanged` events and confirm Fn flag (0x800000) appears. If it doesn't, we pivot to fallbacks.

Fallback options if CGEventTap fails:
1. IOHIDManager (lower level, talks to HID driver directly)
2. NSEvent global monitor (observe-only, no suppression — requires Fn set to "Do Nothing," accepts that we cannot suppress the event)
