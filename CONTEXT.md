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
├── SpaceStation/
│   ├── Sources/
│   │   ├── SpaceStationApp.swift    # App entry point, MenuBarExtra, SetupWindow
│   │   ├── SpaceTracker.swift       # Space detection, switching, permissions
│   │   ├── SpaceNameManager.swift   # Name persistence (UserDefaults)
│   │   ├── MenuBarView.swift        # Main dropdown UI
│   │   ├── SettingsView.swift       # Preferences window
│   │   ├── SwitcherController.swift # Floating Space switcher panel + hotkey wiring
│   │   ├── SwitcherView.swift       # SwiftUI cards for the switcher
│   │   ├── GlobalHotKey.swift       # Carbon RegisterEventHotKey wrapper
│   │   └── HotCorner.swift          # Screen-corner detection + pointer monitor
│   ├── Assets.xcassets/             # App icons (macOS sizes)
│   ├── Info.plist
│   └── SpaceStation.entitlements
├── Tests/SpaceStationTests/         # Unit tests (parsing, shortcuts, name storage)
├── .github/workflows/ci.yml         # Build + test on macOS
├── project.yml                      # XcodeGen definition (source of truth)
├── SpaceStation.xcodeproj           # Generated from project.yml; commit both
├── README.md, CONTRIBUTING.md, SECURITY.md, LICENSE
├── CONTEXT.md                       # This file
└── docs/icon.png                    # README icon
```

### Key Components

#### 1. SpaceStationApp.swift
- **Purpose:** Application entry point
- **Key elements:**
  - `MenuBarExtra` - Creates the menu bar presence
  - `Settings` scene - Preferences window
  - `SetupWindowController` - Standalone NSPanel for permission setup
  - `SetupWindowView` - SwiftUI view for onboarding flow

#### 2. SpaceTracker.swift
- **Purpose:** Core functionality for Space detection and switching
- **Key elements:**
  - `spaces` - Desktop Spaces (`SpaceInfo`: stable `id` + 1-based `index`) on the focused display
  - `currentSpaceIndex` / `currentSpace` - Active desktop (last known one while in fullscreen)
  - `isInFullscreenSpace` - True when the active Space is a fullscreen app
  - `totalSpaces` - Number of desktop Spaces
  - `hasAccessibilityPermission` - Permission status
  - `hasKeyboardShortcutsEnabled` - Detects if Control+1-9 shortcuts are enabled
  - `switchToSpace(_:)` - Switches Spaces by posting the user's configured Desktop shortcut
    (read from `com.apple.symbolichotkeys`) via CGEvent; does nothing if that shortcut is disabled
- **Private APIs used:**
  - `CGSMainConnectionID()` - Gets WindowServer connection
  - `CGSCopyManagedDisplaySpaces()` - Returns Space information

#### 3. SpaceNameManager.swift
- **Purpose:** Persists custom Space names
- **Storage:** UserDefaults with JSON encoding
- **Key:** `SpaceStationNamesByID` stores a `[String: String]` mapping of Space ID to name.
  Space IDs are the Space's `uuid` (falling back to `managed-<ManagedSpaceID>`), so names
  survive reordering. The old position-keyed `SpaceStationNames` key is migrated once and removed.
- **Limits:** names are capped at `SpaceNameManager.maxNameLength` (40) characters

#### 4. MenuBarView.swift
- **Purpose:** Main dropdown menu UI
- **Features:**
  - Permission warning banner
  - Current Space header
  - List of all Spaces (clickable to switch)
  - Inline renaming
  - Settings and Quit buttons

#### 5. SettingsView.swift
- **Purpose:** Preferences window
- **Tabs:**
  - General (Launch at Login)
  - Space Names (bulk editing)
  - About (credits, version)

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

Switching Spaces is done by simulating the keyboard shortcut the user has configured for
"Switch to Desktop N" (normally Control+Number). The key code and modifiers come from
`com.apple.symbolichotkeys`, and nothing is posted if that shortcut is disabled:
```swift
let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true)
keyDown.flags = shortcut.flags
keyDown.post(tap: .cghidEventTap)
```

This requires:
1. Accessibility permission granted
2. "Switch to Desktop N" shortcuts enabled in System Settings

---

## Permissions Required

| Permission | Purpose | How to Grant |
|------------|---------|--------------|
| Accessibility | Post keyboard events to switch Spaces | System Settings → Privacy & Security → Accessibility |
| Keyboard Shortcuts | Enable Control+1-9 for Space switching | System Settings → Keyboard → Keyboard Shortcuts → Mission Control |

---

## Known Issues & Limitations

### 1. Permission Detection After Rebuild
**Issue:** Accessibility permission returns false after rebuilding
**Cause:** Ad-hoc signing changes code signature hash
**Workaround:** Click "Reset & try again" or sign with Developer ID

### 2. macOS Version Compatibility
**Issue:** Private APIs may change
**Mitigation:** Graceful fallback to "Desktop 1" if detection fails

### 3. Maximum 9 Spaces for Switching
**Issue:** Keyboard shortcuts only support Spaces 1-9
**Reason:** macOS only provides Control+1 through Control+9 shortcuts

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
1. **Custom keyboard shortcuts** - Let users define their own shortcuts
2. **Menu bar icon options** - Show icon, text, or both
3. **Space indicators** - Show dots for each Space
4. **Auto-naming** - Name Spaces based on active app
5. **iCloud sync** - Sync names across machines (would require entitlements)

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
- No network access
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

*Last updated: January 2026*
