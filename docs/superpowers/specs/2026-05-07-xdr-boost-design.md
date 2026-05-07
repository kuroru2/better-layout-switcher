# XDR Boost in FnSwitch — Design Spec

## Problem

The existing third-party "XDR range extender" boosts display brightness above the SDR cap, but flickers/blinks every time the user switches macOS Spaces (desktops). The flicker is visually disruptive enough that the user wants to replace the tool. A dedicated rebuild that gets the window-level and Space-membership flags right will fix the blink. Adding it as a feature inside FnSwitch (already in the tray) avoids a second tray icon for what is, for this user, a small set-and-forget control.

## Solution

Add an "XDR Boost" feature to FnSwitch. It overlays a transparent fullscreen window per display whose `CAMetalLayer` contains EDR (extended dynamic range) content — the same mechanism Vivid-style apps use to push the display into HDR mode and unlock above-SDR brightness. The overlay is configured to span all Spaces and never get destroyed on Space switches, eliminating the blink.

The tray menu gains an enable toggle and a level slider (1.0× – 4.0×). State persists across launches via UserDefaults.

## Scope

### Delivers

1. **`XDRBoostController`** — owns per-screen overlay windows, observes screen-configuration changes, persists state, exposes `setEnabled(_:)` / `setLevel(_:)`.
2. **`XDROverlayWindow`** — `NSWindow` subclass with the anti-flicker `collectionBehavior` and window level.
3. **`XDRBoostMetalView`** — `NSView` with a `CAMetalLayer` that renders an EDR fill at the configured boost level.
4. **Tray menu UI** — section divider, "XDR Boost" header label, "Enable" checkbox menu item, custom NSView menu item containing an `NSSlider` and a value label.
5. **Persistence** — `xdrBoostEnabled` (Bool, default false) and `xdrBoostLevel` (Double, default 1.3) in `UserDefaults`.
6. **Multi-display handling** — one overlay per `NSScreen`; reacts to `NSApplication.didChangeScreenParametersNotification` by reconciling overlays without recreating existing ones.

### Does NOT Deliver

- Per-display independent boost levels (single global level for v1).
- Schedule / time-of-day automation.
- Hotkey to toggle (can come later; `FnTapDetector` is reserved for layout switching).
- Calibration UI or color-profile aware tone mapping. The slider is a perceptual knob, not a nit value.
- Any change to FnSwitch's existing behavior — layout switching, OSD, Fn tap detection, launch-at-login all unchanged.

## Architecture

### File Structure

```
Sources/FnSwitch/
├── App.swift                       (modified — instantiate XDRBoostController, pass to StatusBar)
├── FnTapDetector.swift             (unchanged)
├── LayoutManager.swift             (unchanged)
├── OSDWindow.swift                 (unchanged)
├── StatusBarController.swift       (modified — add XDR menu items)
├── XDRBoostController.swift        (new)
├── XDROverlayWindow.swift          (new)
└── XDRBoostMetalView.swift         (new)
```

### File Responsibilities

| File | Responsibility | Depends On |
|------|---------------|-----------|
| `XDRBoostController` | Owns `[NSScreen: XDROverlayWindow]` map. Reads/writes UserDefaults. Reconciles overlays on screen-change notification. Public API: `isEnabled`, `level`, `setEnabled(_:)`, `setLevel(_:)`. | AppKit, the two new views |
| `XDROverlayWindow` | NSWindow subclass; sets `styleMask = .borderless`, `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = false`, `ignoresMouseEvents = true`, `level = .normal − 1`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`. Hosts an `XDRBoostMetalView` as content view. | AppKit |
| `XDRBoostMetalView` | NSView whose layer is a `CAMetalLayer` with `wantsExtendedDynamicRangeContent = true`, `pixelFormat = .rgba16Float`, `colorspace = extendedLinearDisplayP3` (or sRGB). Re-renders when `level` is set. | Metal, MetalKit, QuartzCore |
| `StatusBarController` (modified) | Adds: separator, disabled "XDR Boost" header, "Enable" toggle item, slider menu item with custom NSView. Holds reference to `XDRBoostController`. | the controller |
| `App.swift` (modified) | Constructs `XDRBoostController` once, hands it to `StatusBarController`. | — |

### Anti-Flicker Contract (the whole point)

These are the rules the overlay window MUST follow. Any deviation will reintroduce the blink we're fixing.

1. The window is created exactly once per `NSScreen` and is never closed/recreated while that screen exists. (Hide via `orderOut(nil)` and show via `orderFront(nil)` if needed; never `close()` and re-instantiate.)
2. `collectionBehavior` MUST include `.canJoinAllSpaces` AND `.stationary`. `.canJoinAllSpaces` makes the window present on every Space; `.stationary` prevents it from animating during Space transitions. Both are needed; either alone is insufficient.
3. The controller does NOT subscribe to `NSWorkspace.activeSpaceDidChangeNotification`. Reacting to Space changes is what causes the blink in the existing extender.
4. `NSApplication.didChangeScreenParametersNotification` is handled by reconciling the screen → window map: add windows for new screens, remove windows for departed screens. Existing windows are left alone (frame updated only if the screen's frame changed).
5. Window level is `.normal − 1` (one below regular content). High enough to be composited; low enough never to grab focus or appear above app windows.
6. `ignoresMouseEvents = true`, `acceptsMouseMovedEvents = false`. Window is fully passive.

### Boost Mechanism

The Metal layer is filled with a translucent EDR color. The component value `c` is taken directly from the slider's `level` (1.0–4.0). Alpha is small (0.02) so the overlay is visually near-invisible while the EDR presence keeps the display in HDR mode and pushes brightness up.

macOS clamps the EDR component to whatever the display can actually deliver at the moment. We do not pre-clamp against `NSScreen.maximumExtendedDynamicRangeColorComponentValue`, because that headroom is a dynamic value that drops as system brightness rises, and pre-clamping wastes the slider's upper range whenever the user is at a brightness step where the OS could still push higher. We do still skip non-EDR displays (headroom == 1.0) because the overlay would be a no-op there.

### State & Persistence

- `UserDefaults.standard` keys: `"xdrBoostEnabled"`, `"xdrBoostLevel"`.
- Defaults: `false` and `1.3`.
- Read on `XDRBoostController.init`; written on every `setEnabled`/`setLevel`.
- On launch, if `xdrBoostEnabled == true`, overlays are constructed and shown immediately.

### Menu Layout (after the change)

```
─────────────────────
 [English (US)]            ← existing, layout name in tray title
─────────────────────
 ☐ Launch at Login         ← existing
─────────────────────
 XDR Boost                 ← new (disabled label item)
 ☐ Enable                  ← new (toggle)
 [────●──────]   1.30×     ← new (slider + value, custom NSView in NSMenuItem)
─────────────────────
 Quit FnSwitch             ← existing
```

The slider menu item uses `NSMenuItem.view` with a small NSView containing `NSSlider(value: 1.0, minValue: 1.0, maxValue: 1.6, ...)` and an `NSTextField` showing the formatted value. Slider sends continuous updates; controller debounces redraws to the next runloop tick.

## Edge Cases

- **No EDR-capable display present.** Headroom is 1.0 on every screen → `c == 1.0` → effectively no-op. Toggle still works (won't crash), no visible effect. This is acceptable for v1.
- **Display sleep / wake.** `didChangeScreenParametersNotification` fires; overlays reconcile. Nothing to do beyond the standard reconcile.
- **Display connect / disconnect.** Same path. Departed screen → its overlay window is closed and removed from the map. New screen → new overlay created in correct state (enabled? then visible at current level).
- **Mission Control / Exposé.** `.fullScreenAuxiliary` lets the overlay appear in those views without being treated as a managed window. Should be invisible there because of low alpha; if it becomes a problem, can be hidden on `NSWorkspace.willActivateMissionControlNotification` — defer to v1.1 if reported.
- **Fullscreen apps (e.g., video players in fullscreen).** The overlay is below them due to window level. EDR mode persists if the app itself uses EDR (most don't); otherwise the OS may drop HDR while the fullscreen app is foremost. Acceptable — replicates Vivid behavior.
- **Boost level changed while disabled.** Stored to UserDefaults; takes effect when next enabled. No redraw triggered.
- **Slider continuous drag.** Controller coalesces redraws via a single pending-flag boolean checked on the next main-runloop tick (not Combine, no debouncing timer).

## Testing

The codebase currently has no tests (per the project-structure spec, the test target is added later when testable logic exists). For this feature:

- `XDRBoostController` boost-value math (`c = 1 + (level − 1) × headroom`) is pure and trivially unit-testable; add a test target only if it grows past one expression.
- Overlay window flag setup is a one-shot init — verifiable by reading the code, not worth a test that mostly mirrors the implementation.
- Anti-flicker behavior is observed manually: enable boost, switch Spaces with `Ctrl+←/→` and four-finger swipes, watch for blink. Repeat with displays connected/disconnected.

Manual verification checklist (for the implementation phase, not part of this spec's deliverables):

1. Enable boost on MacBook Pro XDR display → screen visibly brighter.
2. Switch Space — no blink, no flicker.
3. Drag slider 1.0 → 1.6 — brightness ramps smoothly.
4. Toggle off — overlay vanishes, display returns to SDR brightness.
5. Quit & relaunch — last enabled state and level restored.
6. Plug in / unplug an external display — no crash, overlay reconciles.

## Build / Package Changes

`Package.swift` adds linker frameworks:

```swift
linkerSettings: [
    .linkedFramework("Carbon"),
    .linkedFramework("Cocoa"),
    .linkedFramework("Metal"),       // new
    .linkedFramework("MetalKit"),    // new
    .linkedFramework("QuartzCore"),  // new (CAMetalLayer)
]
```

No changes to `package-app.sh` or `package-dmg.sh`. No new external dependencies.

## Out of Scope (deliberately)

- Cross-app brightness syncing
- Color management / nit-accurate calibration
- Animations on enable/disable (instant transitions are fine)
- Localization of new menu strings (matches existing app — none localized today)
- Keyboard shortcut to toggle
- Per-display level
