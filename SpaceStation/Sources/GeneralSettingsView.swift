import SwiftUI
import ServiceManagement
import os.log

struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var spaceTracker: SpaceTracker
    @ObservedObject var preferences: AppPreferences

    // The system (SMAppService) is the source of truth, not a stored preference, so the toggle
    // can't drift if registration fails or the user changes it in System Settings > Login Items.
    @State private var launchAtLogin = false
    @State private var launchError: String?

    private static let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "Settings")

    /// The window height for this tab's current content (the tab controller resizes to it).
    static func height(needsAccessibility: Bool, shortcutWarnings: Int, launchError: Bool) -> CGFloat {
        560 - 40 + (needsAccessibility ? 96 : 0) + CGFloat(shortcutWarnings) * 76 + (launchError ? 20 : 0)
    }

    var body: some View {
        let summary = model.summary
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
            } footer: {
                if let launchError {
                    Text(launchError).foregroundColor(.red).settingsFooter()
                }
            }

            Section {
                Picker("Show", selection: $preferences.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Shorten long names", isOn: $preferences.shortenMenuBarNames)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Names longer than \(MenuBarFormat.nameLimit) characters are shortened in the menu bar.")
                    .settingsFooter()
            }

            Section {
                if !spaceTracker.hasAccessibilityPermission {
                    SettingsWarningRow(
                        title: "SpaceStation needs Accessibility access",
                        detail: spaceTracker.accessibilityHint.map(SetupWindowView.hintText(for:))
                            ?? "macOS requires it for an app to send the shortcuts that switch Spaces.") {
                        Button("Open Accessibility Settings…") { spaceTracker.openAccessibilitySettings() }
                        Button("Reset & Try Again") { spaceTracker.resetAndRequestPermission() }
                    }
                }

                if summary.hasUnreachableSpaces {
                    SettingsWarningRow(
                        title: "Some Spaces can't be switched to",
                        detail: "They have no “Switch to Desktop” shortcut, and “Move left/right a space” is turned off in macOS, which SpaceStation needs to step to them.") {
                        Button("Open Keyboard Settings…") { SystemSettingsPane.keyboardShortcuts.open() }
                    }
                } else if !summary.missingDesktops.isEmpty {
                    let steps = [summary.moveLeft?.display, summary.moveRight?.display].compactMap { $0 }.joined(separator: " ")
                    SettingsWarningRow(
                        title: "\(SpaceListFormat.describe(summary.missingDesktops)) \(summary.missingDesktops.count == 1 ? "has" : "have") no shortcut",
                        detail: "SpaceStation steps to \(summary.missingDesktops.count == 1 ? "it" : "them") with \(steps), which is slower. Turn on “Switch to Desktop” in Keyboard Settings for instant switching.") {
                        Button("Open Keyboard Settings…") { SystemSettingsPane.keyboardShortcuts.open() }
                    }
                }

                LabeledContent(summary.switchRowLabel) {
                    Text(summary.switchRowValue).foregroundColor(.secondary)
                }
                LabeledContent("Mission Control") {
                    Text(summary.missionControl?.display ?? "Off").foregroundColor(.secondary)
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text(summary.hasSpacesBeyondNine
                     ? "SpaceStation switches Spaces using these macOS shortcuts. Spaces beyond 9 are reached by stepping with \(summary.moveLeft?.display ?? "⌃←") \(summary.moveRight?.display ?? "⌃→")."
                     : "SpaceStation switches Spaces using these macOS shortcuts.")
                    .settingsFooter()
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refresh()
            refreshLaunchAtLogin()
        }
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)")
            launchError = "Couldn't \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
        if SMAppService.mainApp.status == .requiresApproval {
            launchError = "Approve SpaceStation in System Settings → General → Login Items."
        }
        refreshLaunchAtLogin()
    }
}
