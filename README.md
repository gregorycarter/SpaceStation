# SpaceStation

<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="SpaceStation Icon">
</p>

A macOS menu bar app for naming and managing Spaces (virtual desktops).

## Features

- Custom names for each Space instead of "Desktop 1", "Desktop 2", …
- The current Space's name shown in the menu bar
- Click a Space in the menu to switch to it (Desktops 1–9)
- A floating **Space switcher** strip showing your names, opened with ⌃S or from the menu
  (macOS offers no way to rename the labels in Mission Control itself, so SpaceStation provides its own)
- Names follow the Space, even if you reorder or add Spaces in Mission Control
- Names stored locally; no network access, no analytics

## Requirements

- macOS 13.0 or later
- To build: Xcode 15 or later

## Install

Download the latest `.dmg` from the [Releases](../../releases) page, drag
SpaceStation to Applications and launch it. It runs in the menu bar only (no Dock icon).

### Setup

Switching Spaces needs two things, and the app walks you through them on first use:

1. **Accessibility permission** (System Settings → Privacy & Security → Accessibility).
   macOS requires this for an app to send the keyboard shortcut that switches Spaces.
   SpaceStation only sends the "Switch to Desktop N" shortcut you configured, and only
   when you click a Space. It never reads your keystrokes.
2. **Enable "Switch to Desktop N"** in System Settings → Keyboard → Keyboard Shortcuts →
   Mission Control.

Naming Spaces and showing the current name work without either.

## Build from source

```bash
brew install xcodegen      # only needed if you change project.yml
open SpaceStation.xcodeproj
```

or from the command line:

```bash
xcodebuild -project SpaceStation.xcodeproj -scheme SpaceStation -configuration Release build
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [CONTEXT.md](CONTEXT.md) for the architecture.

## Limitations

- **Private APIs.** macOS has no public API to find out *which* Space is active, so
  SpaceStation reads it using two undocumented WindowServer functions
  (`CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces`). They are read-only, but a macOS
  update could break them; the app then falls back to a generic "Desktop 1" label.
- **Not on the Mac App Store.** Those APIs, and the lack of sandboxing, rule it out.
- Only Desktops 1–9 can be switched to from the menu (macOS provides no shortcut beyond 9).
- Fullscreen apps are separate Spaces and are shown as "Full Screen".

## Security

See [SECURITY.md](SECURITY.md) for what the app does and doesn't do, and how to report a problem.

## License

[MIT](LICENSE) © Gregory Carter
