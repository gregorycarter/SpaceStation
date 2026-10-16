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
        var height: CGFloat = 650   // launch, menu bar, updates and shortcuts sections
        if needsAccessibility { height += 96 }
        height += CGFloat(shortcutWarnings) * 76
        if launchError { height += 20 }
        return height
    }

    var body: some View {
        Form {
            launchSection
            menuBarSection
            updatesSection
            shortcutsSection
        }
        .formStyle(.grouped)
        .onAppear {
            model.refresh()
            refreshLaunchAtLogin()
        }
    }

    // MARK: - Sections

    private var launchSection: some View {
        Section {
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
        } footer: {
            if let launchError {
                Text(launchError).foregroundColor(.red).settingsFooter()
            }
        }
    }

    private var menuBarSection: some View {
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
    }

    private var updatesSection: some View {
        Section {
            Toggle("Check for updates automatically", isOn: $preferences.checkForUpdatesAutomatically)
        } header: {
            Text("Updates")
        } footer: {
            Text("When on, SpaceStation asks GitHub once a day whether a new version exists. It sends nothing but a generic request and never downloads or installs anything. When off, it only connects if you choose Check for Updates.")
                .settingsFooter()
        }
    }

    private var shortcutsSection: some View {
        let summary = model.summary
        return Section {
            if !spaceTracker.hasAccessibilityPermission { accessibilityWarning }
            shortcutWarning(summary)
            LabeledContent(summary.switchRowLabel) {
                Text(summary.switchRowValue).foregroundColor(.secondary)
            }
            LabeledContent("Mission Control") {
                Text(summary.missionControl?.display ?? "Off").foregroundColor(.secondary)
            }
        } header: {
            Text("Keyboard Shortcuts")
        } footer: {
            Text(shortcutsFooter(summary)).settingsFooter()
        }
    }

    private var accessibilityWarning: some View {
        SettingsWarningRow(
            title: "SpaceStation needs Accessibility access",
            detail: spaceTracker.accessibilityHint.map(SetupWindowView.hintText(for:))
                ?? "macOS requires it for an app to send the shortcuts that switch Spaces.") {
            Button("Open Accessibility Settings…") { spaceTracker.openAccessibilitySettings() }
            Button("Reset & Try Again") { spaceTracker.resetAndRequestPermission() }
        }
    }

    @ViewBuilder
    private func shortcutWarning(_ summary: ShortcutSummary) -> some View {
        if summary.hasUnreachableSpaces {
            SettingsWarningRow(
                title: "Some Spaces can't be switched to",
                detail: "They have no “Switch to Desktop” shortcut, and “Move left/right a space” is turned off in macOS, which SpaceStation needs to step to them.") {
                Button("Open Keyboard Settings…") { SystemSettingsPane.keyboardShortcuts.open() }
            }
        } else if !summary.missingDesktops.isEmpty {
            SettingsWarningRow(
                title: missingTitle(summary),
                detail: missingDetail(summary)) {
                Button("Open Keyboard Settings…") { SystemSettingsPane.keyboardShortcuts.open() }
            }
        }
    }

    private func missingTitle(_ summary: ShortcutSummary) -> String {
        let verb = summary.missingDesktops.count == 1 ? "has" : "have"
        return "\(SpaceListFormat.describe(summary.missingDesktops)) \(verb) no shortcut"
    }

    private func missingDetail(_ summary: ShortcutSummary) -> String {
        let steps = [summary.moveLeft?.display, summary.moveRight?.display].compactMap { $0 }.joined(separator: " ")
        let them = summary.missingDesktops.count == 1 ? "it" : "them"
        return "SpaceStation steps to \(them) with \(steps), which is slower. Turn on “Switch to Desktop” in Keyboard Settings for instant switching."
    }

    private func shortcutsFooter(_ summary: ShortcutSummary) -> String {
        guard summary.hasSpacesBeyondNine else { return "SpaceStation switches Spaces using these macOS shortcuts." }
        let left = summary.moveLeft?.display ?? "⌃←"
        let right = summary.moveRight?.display ?? "⌃→"
        return "SpaceStation switches Spaces using these macOS shortcuts. Spaces beyond 9 are reached by stepping with \(left) \(right)."
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
