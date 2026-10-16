# SpaceStation - Technical Context

This document provides comprehensive context for developers or AI agents working on SpaceStation.

## Overview

**SpaceStation** is a macOS menu bar application that allows users to name and manage their virtual desktop Spaces. It displays the current Space name in the menu bar and allows switching between Spaces by clicking or using keyboard shortcuts.

**Author:** Gregory Carter (www.gregorycarter.net)
**Repository:** github.com/gregorycarter/SpaceStation
**Platform:** macOS 13.0+
**Language:** Swift 5.9 / SwiftUI

---

## Problem Statement

macOS provides "Spaces" (virtual desktops) via Mission Control, but:
1. Spaces are only labeled "Desktop 1", "Desktop 2", etc.
2. There's no native way to give Spaces custom names
3. No public API exists to detect *which* Space is currently active

SpaceStation solves these problems by:
- Tracking the current Space index using private APIs
- Allowing custom names for each Space
- Displaying the current Space name in the menu bar
- Enabling click-to-switch and keyboard shortcut switching

---

## Architecture

### Project Structure

```
SpaceStation/
├── SpaceStation/Sources/
│   ├── SpaceStationApp.swift        # AppKit entry point + AppDelegate (owns models, wires everything)
│   ├── StatusItemController.swift   # NSStatusItem + native NSMenu (Spaces, ⌥ Rename alternates)
│   ├── SpaceTracker.swift           # Observes Spaces, coordinates switching, forwards permission state
│   ├── SpaceSnapshot.swift          # Shared WindowServer parser: desktops and full stepping order
│   ├── SpaceSwitchExecutor.swift    # Key posting, settling and bounded corrections; injectable time/effects
│   ├── AccessibilityController.swift # Permission checks, signing history and stale-grant recovery
│   ├── SpaceStepper.swift           # SpaceOrder, stepping plan, previous-Space history (pure)
│   ├── SystemShortcuts.swift        # KeyBinding, symbolichotkeys + Dock hot-corner readers (pure)
│   ├── SpaceNameManager.swift       # Names + icons by Space ID (UserDefaults)
│   ├── SpaceNameRules.swift         # Editing limits, saved-name normalization and default labels
│   ├── SpaceIcon.swift / SpaceIconImage.swift  # Icon model; NSImage rendering for menus
│   ├── AppPreferences.swift         # Typed settings + migration from the old Control+S switch
│   ├── Switcher*.swift              # Panel controller, SwiftUI cards, pure layout/placement
│   ├── GlobalHotKey.swift, HotCorner.swift, KeyRecorder.swift, CornerMapView.swift
│   ├── Settings*.swift, *SettingsView.swift  # Toolbar-tab Settings window + tabs, shared logic
│   ├── RenamePopover.swift, RenameDraft.swift, IconPickerView.swift
│   ├── SetupWindow.swift            # First-run / Accessibility window
│   ├── UpdateChecker.swift, UpdatePresenter.swift, StatusItemBadge.swift  # Optional "Check for Updates" + menu bar dot
│   ├── CodeSigning.swift            # Detects stale permission after a signature change
│   └── RenderGallery.swift          # DEBUG only: renders views to PNG offscreen
├── Tests/SpaceStationTests/         # Host-less unit tests of the pure logic and menu structure
├── Config/                          # Shared.xcconfig (+ git-ignored Local.xcconfig for signing)
├── .github/workflows/ci.yml         # Build + test on macOS
├── project.yml                      # XcodeGen definition (source of truth)
├── SpaceStation.xcodeproj           # Generated from project.yml; commit both
├── README.md, CONTRIBUTING.md, SECURITY.md, LICENSE
├── CONTEXT.md                       # This file
└── docs/icon.png                    # README icon
```

### How it fits together

- **Status item and menu:** `StatusItemController` builds a real `NSMenu` each time it opens, so it
  always reflects the current Space, names, icons and the user's shortcuts. Option alternates turn
  each Space row into its Rename action. Rename shows an `NSPopover` anchored to the status button.
  Menu construction takes a `StatusMenuSnapshot`, so tests cover explicit desktop, fullscreen,
  permission and remapped-shortcut fixtures without consulting the running Mac.
- **Switching** (`SpaceTracker.switchTo`): use the user's "Switch to Desktop N" shortcut when macOS
  has one enabled (1–9); otherwise step with "Move left/right a space", counting fullscreen Spaces
  in the way (`SpaceOrder`/`SpaceStepper`). Presses are sent back to back (100 ms apart) and the
  result is verified and corrected. It never posts a key that isn't an enabled macOS shortcut.
  `SpaceSwitchExecutor` owns the sequence; injected key posting, snapshots and time let tests cover
  arrival, overshoot, timeout, the two-correction limit and suppression of intermediate history.
- **Switcher panel:** a non-activating, floating, all-Spaces `NSPanel` (this configuration is what
  lets it appear over fullscreen apps and take the hotkey; change it with care) with a rounded
  `NSVisualEffectView` background and SwiftUI cards. Opened by the user-recorded hotkey, the menu, or
  the hot corner. Layout, hit-testing and placement are pure functions in `SwitcherLayout.swift`.
  `AppDelegate` owns the controller and supplies its dependencies at construction, prewarming it
  and registering its triggers during startup.
- **Hot corner:** `HotCornerMonitor` samples `NSEvent.mouseLocation` every 20 ms (no permission, and
  it works for a pointer resting in a corner, which sends no events). `HotCornerTrigger` is a pure
  dwell/re-arm state machine; the user's delay (Instant to Long) is its dwell.
- **Settings:** an `NSTabViewController` (toolbar style) hosting SwiftUI grouped forms. It is built
  directly because the SwiftUI Settings scene is unreliable for an app with no Dock icon.
- **Permissions:** Accessibility only. `AccessibilityController` owns permission checks and recovery;
  `CodeSigning` identifies signature changes. `SpaceTracker` forwards published permission state to
  existing views. Tests inject system operations and isolated defaults rather than touching TCC.

### Debug-only hooks

Compiled out of Release builds:
- `SPACESTATION_RENDER_DIR=<dir>`: render the main views to PNGs offscreen and exit (no menu bar item,
  hotkeys or windows). Blur materials don't render offscreen, so backgrounds are flat.
- `SPACESTATION_DEBUG_SWITCH=<n>`: switch to desktop n two seconds after launch (no keystrokes needed).
- `SPACESTATION_DEBUG_FORCE_STEP=1`: with the above, use arrow-key stepping even when a direct shortcut exists.
- `SPACESTATION_DEBUG_STEP_INTERVAL_MS=<ms>`: override the stepping press interval.

---

## Technical Decisions

### Why Private APIs?

Apple provides **no public API** to determine which Space is active. The only public API is `NSWorkspace.activeSpaceDidChangeNotification` which notifies that a change occurred but not *which* Space is now active.

We use:
```swift
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: Int) -> CFArray?
```

**Trade-off:** Private APIs may break with macOS updates, but there's no alternative for this functionality.

### Why Non-Sandboxed?

The app cannot be sandboxed because:
1. Private APIs require direct WindowServer communication
2. Reading `com.apple.symbolichotkeys` prefs requires unsandboxed access
3. `CGEvent` posting for keyboard simulation has restrictions

**Consequence:** Cannot distribute via Mac App Store.

### Why Ad-Hoc Signing Causes Permission Issues

macOS TCC (Transparency, Consent, and Control) tracks permissions by:
- Bundle Identifier + Code Signature Hash

With ad-hoc signing, each rebuild generates a new code signature hash. macOS sees each build as a "different app" and invalidates the previous accessibility permission.

**Solution for development:** Sign with a stable certificate (see CONTRIBUTING.md and
`Config/Local.xcconfig.example`), or use the "Reset & try again" button which runs `tccutil reset`.
The app detects ad-hoc signing (`CodeSigning.swift`) and tells the user when the build has
changed since access was last granted.
**Solution for distribution:** Sign with Apple Developer ID ($99/year)

### Keyboard Shortcut Detection

System keyboard shortcuts are stored in:
```
~/Library/Preferences/com.apple.symbolichotkeys.plist
```

Keys 118-126 correspond to "Switch to Desktop 1-9". We read this plist to detect if shortcuts are enabled.

### Space Switching Implementation

SpaceStation switches Spaces by posting one of macOS's own shortcuts, never a key of its own:

1. If macOS has "Switch to Desktop N" enabled for that Space (1–9), post it. The key code and
   modifiers come from `com.apple.symbolichotkeys`, so a remapped shortcut still works.
2. Otherwise step there with "Move left/right a space" (default ⌃← / ⌃→), pressing it once per Space
   in the way (fullscreen Spaces count). Presses are sent 100 ms apart, then the result is checked
   and corrected, so seven steps take about a second.
3. If neither is available the switch is refused (`SwitchOutcome.unavailable`) and Settings →
   General explains why, rather than sending a key into whatever app is in front.

```swift
let keyDown = CGEvent(keyboardEventSource: source, virtualKey: binding.keyCode, keyDown: true)
keyDown.flags = binding.flags
keyDown.post(tap: .cghidEventTap)
```

This requires Accessibility permission. The "Switch to Desktop" shortcuts are optional (instant
switching); the "Move a space" shortcuts are on by default in macOS.

---

## Permissions Required

| Permission | Purpose | How to Grant |
|------------|---------|--------------|
| Accessibility | Post the shortcuts that switch Spaces | System Settings → Privacy & Security → Accessibility |

Nothing else is requested. (Reading the shortcut and Dock preferences, sampling the pointer for the
hot corner and registering the hotkey need no permission.)

---

## Known Issues & Limitations

### 1. Permission Detection After Rebuild
**Issue:** Accessibility permission returns false after rebuilding
**Cause:** Ad-hoc signing changes the code signature hash
**Handling:** `CodeSigning` detects it and clears the stale entry once; sign local builds with a stable
certificate (see CONTRIBUTING.md) to avoid it entirely

### 2. macOS Version Compatibility
**Issue:** Private APIs may change
**Mitigation:** Graceful fallback to "Desktop 1" if detection fails

### 3. Spaces without a "Switch to Desktop" shortcut
**Issue:** macOS only provides "Switch to Desktop N" shortcuts for Desktops 1-9, and they are off until enabled
**Handling:** Those Spaces (and all beyond 9) are reached by stepping with the "Move left/right a space"
shortcuts, which is slower. If those are off too, the Space can't be switched to and Settings says so.

### 4. Fullscreen Apps
**Issue:** Fullscreen apps create their own Spaces
**Handling:** We filter these out (type != 0) to only list desktop Spaces. While a fullscreen
Space is active the menu bar shows "Full Screen" and no desktop is highlighted.

---

## Build & Distribution

### Development Build
```bash
cd path/to/SpaceStation
xcodebuild -project SpaceStation.xcodeproj -scheme SpaceStation -configuration Debug build
```

### Release Build
```bash
xcodebuild -project SpaceStation.xcodeproj -scheme SpaceStation -configuration Release clean build
```

### Create DMG
```bash
APP_PATH=~/Library/Developer/Xcode/DerivedData/SpaceStation-*/Build/Products/Release/SpaceStation.app
mkdir -p /tmp/SpaceStation-dmg
cp -R "$APP_PATH" /tmp/SpaceStation-dmg/
ln -sf /Applications /tmp/SpaceStation-dmg/Applications
hdiutil create -volname "SpaceStation" -srcfolder /tmp/SpaceStation-dmg -ov -format UDZO ~/Desktop/SpaceStation.dmg
rm -rf /tmp/SpaceStation-dmg
```

### Install Locally
```bash
cp -R "$APP_PATH" /Applications/
```
A locally built app carries no quarantine flag, so it launches normally.

### Releases (Developer ID + notarization)
Hardened Runtime is enabled. For public releases, sign with a Developer ID
Application certificate, notarize (`xcrun notarytool submit ... --wait`), then staple
(`xcrun stapler staple SpaceStation.app`) before creating the DMG. Don't tell users to
strip the quarantine attribute (`xattr -cr`); an unsigned build can be opened with
right-click → Open, and a notarized one needs nothing.

---

## Project Generation

The Xcode project is generated from `project.yml` using XcodeGen:
```bash
xcodegen generate
```

Key settings in `project.yml`:
- `deploymentTarget: macOS 13.0`
- `LSUIElement: true` (no dock icon)
- `ENABLE_HARDENED_RUNTIME: true` (required for notarization)
- Non-sandboxed (`com.apple.security.app-sandbox: false`)

---

## Future Improvements

Potential enhancements not yet implemented:
1. **Auto-naming** - Name Spaces based on active app
2. **iCloud sync** - Sync names across machines (would require entitlements)

---

## Dependencies

**None.** The app uses only Apple system frameworks:
- SwiftUI
- AppKit
- ApplicationServices
- ServiceManagement
- os.log

---

## Security Considerations

See `SECURITY.md` for the full security analysis and vulnerability reporting.

Summary:
- No network access except the opt-in update check (one anonymous GET to GitHub's releases API; never downloads or installs)
- No file system access beyond preferences (plus read-only access to the system's shortcut preferences)
- No third-party dependencies
- Local-only data storage
- Private APIs are read-only

---

## Useful Commands

```bash
# Check accessibility permission status
tccutil reset Accessibility com.gregorycarter.SpaceStation

# View logs
log stream --predicate 'subsystem == "com.gregorycarter.SpaceStation"'

# Check code signature
codesign -dv /Applications/SpaceStation.app

# Read keyboard shortcuts plist
defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys
```

---

*Last updated: October 2026*
