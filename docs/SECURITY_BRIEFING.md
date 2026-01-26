# SpaceStation Application Security Briefing

**Document Version:** 1.0
**Date:** January 26, 2026
**Classification:** Internal Review

---

## Executive Summary

SpaceStation is a local-only macOS menu bar utility that names and tracks virtual desktop Spaces. The application is designed with a minimal attack surface: **no network access, no cloud services, no inter-process communication with third-party applications, and no access to user documents or sensitive data.**

---

## 1. Application Scope & Boundaries

### What SpaceStation Does
- Reads the current Space index from macOS window management APIs
- Stores custom Space names locally
- Displays information in the menu bar
- Responds to user input to rename Spaces or switch between them

### What SpaceStation Does NOT Do
| Capability | Status |
|------------|--------|
| Network/Internet access | **None** |
| Cloud sync or telemetry | **None** |
| File system access (Documents, Downloads, etc.) | **None** |
| Access to other applications' data | **None** |
| Keychain access | **None** |
| Camera/Microphone access | **None** |
| Location services | **None** |
| Contacts, Calendar, Reminders | **None** |
| Screen recording or capture | **None** |
| Accessibility API (reading other app content) | **None** |

---

## 2. Data Handling

### Data Collected
| Data | Purpose | Storage Location |
|------|---------|------------------|
| Custom Space names | User-defined labels | `UserDefaults` (local plist) |
| Current Space index | Display in menu bar | Memory only (not persisted) |
| Launch-at-login preference | User preference | `UserDefaults` (local plist) |

### Data NOT Collected
- No usage analytics or telemetry
- No crash reports sent externally
- No user behavior tracking
- No screenshots or Space contents
- No application usage from other apps

### Storage Security
- All data stored in app-sandboxed `UserDefaults`
- Location: `~/Library/Preferences/com.gregorycarter.SpaceStation.plist`
- No encryption required (data is non-sensitive Space names only)
- No export functionality

---

## 3. System API Usage

### Public APIs Used
| API | Purpose | Risk Level |
|-----|---------|------------|
| `NSWorkspace.activeSpaceDidChangeNotification` | Detect Space changes | **Low** - Standard notification |
| `MenuBarExtra` (SwiftUI) | Menu bar presence | **Low** - Standard UI component |
| `UserDefaults` | Preference storage | **Low** - Sandboxed storage |
| `SMAppService` | Launch at login | **Low** - Standard macOS service |

### Private APIs Used (Requires Review)
| API | Purpose | Risk Assessment |
|-----|---------|-----------------|
| `CGSMainConnectionID()` | Get window server connection | **Medium** - Private but read-only |
| `CGSCopyManagedDisplaySpaces()` | Query Space information | **Medium** - Private but read-only |

#### Private API Risk Mitigation
1. **Read-only operations**: These APIs only query state; they cannot modify system configuration
2. **No privilege escalation**: APIs run with standard user permissions
3. **Graceful degradation**: If APIs fail (e.g., after macOS update), app falls back to default behavior
4. **No injection risk**: No data from these APIs is executed or used in shell commands

#### Private API Stability Concern
- Private APIs may break with macOS updates
- This affects **functionality only**, not security
- Fallback: App displays "Desktop 1" if Space detection fails

---

## 4. Permissions & Entitlements

### Current Entitlements (`SpaceStation.entitlements`)
```xml
<key>com.apple.security.app-sandbox</key>
<false/>

<key>com.apple.security.automation.apple-events</key>
<true/>
```

### Entitlement Analysis

| Entitlement | Justification | Risk |
|-------------|---------------|------|
| `app-sandbox: false` | Required for CGS private APIs to query Space info | **See Section 5** |
| `automation.apple-events` | Future: keyboard shortcuts to switch Spaces | **Low** - User-initiated only |

### Permissions NOT Requested
- No Accessibility permissions
- No Full Disk Access
- No Screen Recording
- No Input Monitoring
- No Developer Tools access

---

## 5. Sandboxing Analysis

### Current State: Non-Sandboxed

The app currently runs **outside the sandbox** because:
1. `CGSCopyManagedDisplaySpaces()` requires direct WindowServer communication
2. Sandboxed apps cannot access these private APIs

### Risk Assessment of Non-Sandboxed Operation

| Attack Vector | Mitigation |
|---------------|------------|
| App could access user files | App has no file-handling code; no `NSOpenPanel`, no file APIs imported |
| App could make network requests | App has no networking code; no `URLSession`, no network frameworks imported |
| App could launch other processes | App has no `Process`/`NSTask` usage; no shell execution |
| App could read other apps' memory | Would require additional entitlements not present |

### Code Audit Checklist
- [ ] No `import Network` or `import Foundation.URLSession`
- [ ] No `FileManager` operations outside preferences
- [ ] No `Process` or `NSTask` usage
- [ ] No `dlopen` or dynamic library loading
- [ ] No `NSAppleScript` execution
- [ ] No shell command construction

### Future Consideration: Sandboxed Alternative
A sandboxed version could be built using only `NSWorkspace` notifications (losing precise Space index detection). This would:
- Limit functionality to "Space changed" events only
- Remove ability to show Space numbers
- Enable App Store distribution

---

## 6. Keyboard Shortcut Security

### Implementation
- Uses `CGEvent` to simulate Control+Number keypresses
- Only triggered by explicit user action (clicking menu item)
- Cannot be triggered remotely or programmatically from outside the app

### Risk Assessment
| Concern | Analysis |
|---------|----------|
| Could inject arbitrary keystrokes | **No** - Hardcoded to Control+1-9 only |
| Could be triggered without user action | **No** - Requires UI interaction |
| Could capture keystrokes | **No** - Only posts events, no event tap installed |

---

## 7. Supply Chain Security

### Dependencies
| Dependency | Source | Risk |
|------------|--------|------|
| Swift Standard Library | Apple | **None** - System framework |
| SwiftUI | Apple | **None** - System framework |
| AppKit | Apple | **None** - System framework |
| ServiceManagement | Apple | **None** - System framework |

**No third-party dependencies.** The app uses only Apple system frameworks.

### Build Security
- Built locally using Xcode
- No external build services
- No package managers (CocoaPods, SPM dependencies)
- Source available for audit at `github.com/gregorycarter/SpaceStation`

---

## 8. Threat Model

### Threats NOT Applicable
| Threat | Why N/A |
|--------|---------|
| Data exfiltration | No network access |
| Man-in-the-middle | No network access |
| Server compromise | No server |
| Credential theft | No credentials stored |
| Privilege escalation | Runs as standard user |
| Cross-site scripting | No web views |
| SQL injection | No database |

### Residual Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Private API changes break app | Medium | Low (functionality only) | Graceful fallback |
| Malicious code injection via fork | Low | High | Sign releases, verify checksums |
| Local privilege escalation via app | Very Low | Medium | No setuid, no elevated operations |

---

## 9. Recommendations

### For Initial Release
1. **Code-sign the application** with a Developer ID certificate
2. **Notarize with Apple** to pass Gatekeeper checks
3. **Document the private API usage** in README for transparency

### For Future Versions
1. Evaluate sandboxed alternative if precise Space detection becomes available via public API
2. Consider App Store distribution (requires sandboxing)
3. Implement update mechanism with signature verification if distributing outside App Store

### Not Recommended
- Do not add analytics or telemetry
- Do not add network features
- Do not add file import/export
- Do not request additional permissions

---

## 10. Verification Steps

To verify security claims, audit the source code for:

```bash
# Check for network code
grep -r "URLSession\|Network\|http\|socket" SpaceStation/Sources/

# Check for file operations
grep -r "FileManager\|NSOpenPanel\|NSSavePanel" SpaceStation/Sources/

# Check for process spawning
grep -r "Process\|NSTask\|shell\|bash\|/bin/" SpaceStation/Sources/

# Check for dynamic code
grep -r "dlopen\|NSBundle.*load\|performSelector" SpaceStation/Sources/
```

Expected result: **No matches** for any of the above.

---

## Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Developer | | | |
| Security Reviewer | | | |

---

*This document should be reviewed and updated with each significant code change.*
