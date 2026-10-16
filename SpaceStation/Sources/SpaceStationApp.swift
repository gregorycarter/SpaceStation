import SwiftUI
import Combine
import os.log

/// Owns the app-wide model objects and finishes startup. Startup work lives here rather than in
/// SwiftUI view callbacks: `.onAppear` on a menu bar item's label does not reliably run at launch,
/// which once left the switcher's hotkey and hot corner unregistered.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let spaceTracker = SpaceTracker()
    let nameManager = SpaceNameManager()
    let preferences = AppPreferences.shared
    let updateChecker = UpdateChecker()
    private var statusItemController: StatusItemController?
    private var subscriptions = Set<AnyCancellable>()
    private lazy var switcherController = SwitcherController(
        spaceTracker: spaceTracker, nameManager: nameManager, preferences: preferences,
        handleOutcome: { [unowned self] outcome in handle(outcome) })

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Names saved by position (before names followed their Space) migrate once real Spaces are known.
        spaceTracker.$spaces
            .sink { [nameManager] spaces in nameManager.migrateLegacyNames(using: spaces) }
            .store(in: &subscriptions)

        statusItemController = StatusItemController(
            spaceTracker: spaceTracker,
            nameManager: nameManager,
            preferences: preferences,
            updateChecker: updateChecker,
            actions: StatusItemController.Actions(
                rename: { [unowned self] space in
                    // The menu has just closed; show the popover under the menu bar item.
                    DispatchQueue.main.async { [self] in
                        RenamePopoverController.shared.show(
                            space: space, anchor: statusItemController?.button, nameManager: nameManager,
                            fallback: { showSettings(tab: .spaces) })
                    }
                },
                showSwitcher: { [unowned self] in switcherController.show(trigger: .menu) },
                showSettings: { [unowned self] in showSettings() },
                showAbout: { [unowned self] in showSettings(tab: .about) },
                allowAccessibility: { [unowned self] in
                    SetupWindowController.shared.showSetupWindow(spaceTracker: spaceTracker)
                },
                checkForUpdates: { [unowned self] in
                    Task { @MainActor in UpdatePresenter.present(await updateChecker.check()) }
                },
                openUpdate: { NSWorkspace.shared.open($0.url) },
                handleSwitchOutcome: { [unowned self] outcome in handle(outcome) }
            )
        )

        // Optional (off by default): look for a new release at launch, at most once a day.
        Task { @MainActor [updateChecker, preferences] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await updateChecker.checkAutomaticallyIfDue(enabled: preferences.checkForUpdatesAutomatically)
        }
        // Prewarm the panel and register triggers at the same point in startup.
        _ = switcherController

        #if DEBUG
        // Test hook (Debug builds only): SPACESTATION_DEBUG_SWITCH=<n> switches to desktop n shortly
        // after launch, so switching can be exercised without sending keystrokes.
        if let value = ProcessInfo.processInfo.environment["SPACESTATION_DEBUG_SWITCH"], let target = Int(value) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [spaceTracker] in
                guard let space = spaceTracker.spaces.first(where: { $0.index == target }) else { return }
                let outcome = spaceTracker.switchTo(space)
                Logger(subsystem: "com.gregorycarter.SpaceStation", category: "DebugHook")
                    .info("debug switch to \(target): \(String(describing: outcome), privacy: .public)")
            }
        }
        #endif
    }

    func showSettings(tab: SettingsTab = .general) {
        SettingsWindowController.shared.show(tab: tab, spaceTracker: spaceTracker, nameManager: nameManager,
                                             preferences: preferences, updateChecker: updateChecker)
    }

    /// What to do when a switch couldn't be made: walk the user through setup.
    func handle(_ outcome: SpaceTracker.SwitchOutcome) {
        switch outcome {
        case .started, .alreadyCurrent: break
        case .needsAccessibility: SetupWindowController.shared.showSetupWindow(spaceTracker: spaceTracker)
        // No shortcut and no way to step to it: Settings > General explains which Spaces and why.
        case .unavailable: showSettings(tab: .general)
        }
    }
}

/// Entry point. The app is an AppKit status item app; SwiftUI is used for the windows.
@main
enum SpaceStationMain {
    private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        #if DEBUG
        // Debug-only: render views to PNG files and exit (no menu bar item, hotkey or windows).
        if let directory = ProcessInfo.processInfo.environment["SPACESTATION_RENDER_DIR"] {
            RenderGallery.run(directory: directory)
            return
        }
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate   // NSApplication only holds its delegate weakly
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
