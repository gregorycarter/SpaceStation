# Security

SpaceStation is a local-only macOS menu bar utility that lets you name your
Spaces (virtual desktops) and switch between them. This document describes what
it does, what it needs, and how to report a problem. It reflects the source in
this repository; if the two disagree, the source wins, and please open an issue.

## Reporting a vulnerability

Please report security issues privately using GitHub's
["Report a vulnerability"](https://github.com/gregorycarter/SpaceStation/security/advisories/new)
button on the repository's Security tab (or email email@gregorycarter.net)
rather than opening a public issue.

## What the app does

- Reads the list of Spaces and the current Space using private WindowServer
  functions (`CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces`). These are
  read-only queries.
- Reads the "Switch to Desktop N" shortcut settings from the system's
  `com.apple.symbolichotkeys` preferences (read-only).
- Switches Spaces by posting the keyboard shortcut you have configured for
  that Desktop (`CGEvent`). This is only done when you click a Space in the menu.
- Stores the names you choose in `UserDefaults`
  (`~/Library/Preferences/com.gregorycarter.SpaceStation.plist`), keyed by
  Space ID.
- Optionally registers itself as a login item via `SMAppService`.
- Registers one global hotkey (Control+S, can be turned off in Settings; note it takes ⌃S away from other apps while enabled) with the
  public Carbon `RegisterEventHotKey` API to show the Space switcher. This only fires
  when that exact combination is pressed and needs no extra permission; it does not
  observe other keystrokes.
- Optionally (off by default) watches the pointer position to open the switcher from a screen
  corner, using a global mouse-moved monitor. macOS requires no permission for mouse movement
  (only keyboard events), and the app only compares the pointer position to the screen corner;
  it does not record or store it.

## What the app does not do

- No network access: no `URLSession`, sockets or analytics. The only URL it can
  open is a link to the author's website (About tab, opened in your browser) and
  System Settings deep links.
- No file access beyond its own preferences: no `FileManager`, open/save panels
  or document handling.
- No event taps or keystroke capture. It only *posts* key events; it never
  *reads* your keyboard input or other apps' content.
- No screen recording, camera, microphone, location, contacts or keychain access.
- No dynamic code loading or AppleScript.

## Permissions and entitlements

| Item | Why |
|------|-----|
| Accessibility (user-granted in System Settings) | Required by macOS to post the Control+number key events that switch Spaces. |
| `com.apple.security.app-sandbox = false` | The private Space APIs and the system shortcut preferences are not available to sandboxed apps. |
| Hardened Runtime: enabled | Required for notarization; no exceptions are requested. |

Because the app is not sandboxed and holds Accessibility permission, it can
post keystrokes to any app. The code is limited to the single configured
Desktop shortcut and only runs on a click; the permission is the reason to
install only builds you trust (build from source, or use a notarized release).

## Subprocess use

The "Permission not detected? Reset & try again" button runs
`/usr/bin/tccutil reset Accessibility <this app's bundle id>`. The arguments
are fixed (no user input is interpolated). This resets only SpaceStation's own
Accessibility entry and exists mainly to recover from permission mismatches
after rebuilding unsigned development builds.

## Private APIs

The two CGS functions above are undocumented and may change in a macOS update.
That affects functionality (the app falls back to showing a single "Desktop 1"
placeholder), not security. They are not available to App Store apps, so the
app cannot be distributed through the Mac App Store.

## Data

- Stored: your Space names and the Launch at Login state (held by the system,
  not by the app). Names are plain text and are not encrypted.
- Not collected: usage, analytics, crash reports, window or app contents.
- Logging uses `os.log`. Space names are not written to the log.

## Supply chain

No third-party dependencies; only Apple system frameworks (SwiftUI, AppKit,
ApplicationServices, ServiceManagement). Releases should be signed with a
Developer ID certificate and notarized. Do not follow advice to strip the
quarantine attribute (`xattr -cr`) from downloads of unknown origin.

## Verifying these claims

```bash
grep -rnE "URLSession|Network|http|socket" SpaceStation/Sources/    # only the About link
grep -rnE "FileManager|NSOpenPanel|NSSavePanel" SpaceStation/Sources/ # none
grep -rnE "Process\(|NSTask|/bin/" SpaceStation/Sources/              # tccutil only
grep -rnE "dlopen|performSelector|NSAppleScript" SpaceStation/Sources/ # none
```
