# FnSwitch

A lightweight macOS keyboard layout switcher that lives in your menu bar. Switches layouts with a quick Fn key tap, shows a consistent OSD every time.

Built with Swift and AppKit. macOS 14+ (Sonoma).

## Why

macOS Fn-based layout switching is unreliable on macOS 15 — the key often requires multiple presses, and the system OSD is inconsistent (sometimes near cursor, sometimes as OSD, sometimes only in tray). FnSwitch takes over: intercepts Fn taps at the system level, switches layouts itself, and always shows a clear centered OSD.

## Features

- **Fn tap detection** — distinguishes quick taps from Fn-as-modifier (Fn+F1, etc.)
- **Reliable switching** — uses TIS APIs directly, no macOS middleman
- **Consistent OSD** — always shows layout name centered on screen
- **Menu bar app** — runs in the background, current layout shown in tray
- **Configurable threshold** — 300ms tap detection (hardcoded for now)

## Install

Download the latest `.dmg` from [Releases](../../releases).

> **Note:** The app is not code-signed. macOS will show a warning. To fix:
> ```bash
> xattr -cr /Applications/FnSwitch.app
> ```

### Prerequisites

Before running FnSwitch:

1. Set Fn key to "Do Nothing" in **System Settings > Keyboard > "Press globe key to"**
2. Grant Accessibility permission: **System Settings > Privacy & Security > Accessibility** — add FnSwitch (or Terminal if running from source)

## Development

### Build

```bash
swift build
.build/debug/FnSwitch
```

### Package

```bash
scripts/package-app.sh    # → build/FnSwitch.app
scripts/package-dmg.sh    # → FnSwitch-macOS.dmg
```

### Release

```bash
scripts/release.sh patch   # bumps version, tags
git push && git push --tags # triggers GitHub Actions release
```

### Lint

```bash
swiftlint lint --strict
```

## Architecture

```
Sources/FnSwitch/
├── main.swift                # Entry point, AppDelegate, wires components
├── FnTapDetector.swift       # CGEventTap — Fn key tap vs modifier detection
├── LayoutManager.swift       # TIS APIs — enumerate and switch input sources
├── OSDWindow.swift           # Borderless overlay — layout name display
└── StatusBarController.swift # Menu bar — current layout + quit
```

## License

MIT
