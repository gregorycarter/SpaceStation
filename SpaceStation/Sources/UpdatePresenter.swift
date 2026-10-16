import AppKit

/// Shows the result of a manual "Check for Updates…" in an alert.
@MainActor
enum UpdatePresenter {
    static func present(_ status: UpdateStatus, currentVersion: String = UpdateChecker.bundleVersion) {
        let alert = NSAlert()
        switch status {
        case .available(let release):
            alert.messageText = "SpaceStation \(release.version) is available"
            alert.informativeText = "You have \(currentVersion). Download the new version from GitHub and replace the app. SpaceStation never downloads or installs anything itself."
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.url) }
            return
        case .upToDate(let version):
            alert.messageText = "You're up to date"
            alert.informativeText = "SpaceStation \(version) is the latest version."
        case .noReleases:
            alert.messageText = "No releases yet"
            alert.informativeText = "No version of SpaceStation has been published on GitHub yet."
        case .failed(let message):
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = message
        }
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
