# SpaceStation

<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="SpaceStation Icon">
</p>

A macOS menu bar app for naming and managing Spaces (virtual desktops).

## Features

- Name your Spaces and give each an **icon** (an SF Symbol or any emoji), instead of "Desktop 1", "Desktop 2", …
- A native **menu bar menu**: the current Space's icon and name, every Space one click away, and
  hold ⌥ to turn the rows into Rename
- A floating **Space switcher** that shows your names and icons, opened with a shortcut you choose
  (default ⌃⌥S), from the menu, or by resting the pointer in a **screen corner**. It opens on the
  previous Space, so open + Return flips between your last two. Pick with the mouse, ← → ↑ ↓,
  **1–9**, or by **typing a name**
  (macOS offers no way to rename the labels in Mission Control itself, so SpaceStation provides its own)
- Works with up to 16 Spaces, including ones beyond macOS's ⌃1–⌃9 shortcuts
- Names and icons follow the Space, even if you reorder or add Spaces in Mission Control
- Detects macOS shortcuts and Hot Corners that would clash, and says so, instead of leaving you to find out
- Names stored locally; no analytics. The only network use is an optional check for a newer version
  on GitHub, when you choose Check for Updates (or turn on the once-a-day check, off by default)

## Requirements

- macOS 13.0 or later
- To build: Xcode 15 or later

## Install

Download the latest `.dmg` from the [Releases](../../releases) page, drag
SpaceStation to Applications and launch it. It runs in the menu bar only (no Dock icon).

### Setup

SpaceStation needs one permission, and walks you through it on first use:

- **Accessibility** (System Settings → Privacy & Security → Accessibility). macOS requires this for
  an app to send the keyboard shortcuts that switch Spaces. SpaceStation only sends macOS's own
  Space shortcuts, only when you pick a Space, and never reads your keystrokes.

Optional, for **instant** switching: turn on "Switch to Desktop N" in System Settings → Keyboard →
Keyboard Shortcuts → Mission Control. Without it SpaceStation still reaches every Space by stepping
with "Move left/right a space" (⌃← ⌃→), which takes about a second for a far Space instead of being
immediate. Settings → General shows which Spaces have a shortcut.

Naming Spaces and showing the current name work without any permission.

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
- Spaces beyond 9 (and any without a "Switch to Desktop" shortcut) are reached by stepping, which is slower, and needs the "Move left/right a space" shortcuts left on in macOS.
- Fullscreen apps are separate Spaces and are shown as "Full Screen".

## Security

See [SECURITY.md](SECURITY.md) for what the app does and doesn't do, and how to report a problem.

## License

[MIT](LICENSE) © Gregory Carter
