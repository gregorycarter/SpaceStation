import SwiftUI
import AppKit

enum SettingsTab: Int, CaseIterable {
    case general, switcher, spaces, about

    var title: String {
        switch self {
        case .general: return "General"
        case .switcher: return "Switcher"
        case .spaces: return "Spaces"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .switcher: return "rectangle.split.3x1"
        case .spaces: return "square.grid.2x2"
        case .about: return "info.circle"
        }
    }
}

/// NSTabViewController owns its tab view's delegate (assigning another one is an assertion
/// failure), so tab changes are observed by overriding the delegate method here.
private final class SettingsTabViewController: NSTabViewController {
    var onSelectTab: ((SettingsTab) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let tabViewItem, let tab = SettingsTab(rawValue: tabView.indexOfTabViewItem(tabViewItem)) else { return }
        onSelectTab?(tab)
    }
}

/// The Settings window: a standard toolbar-style tab window (like System Settings' older panes)
/// whose tabs are SwiftUI grouped forms. It is built directly rather than as a SwiftUI Settings
/// scene, which is unreliable for apps with no Dock icon.
@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    static let width: CGFloat = 560

    private var window: NSWindow?
    private var tabController: SettingsTabViewController?
    private var model: SettingsModel?

    private override init() { super.init() }

    #if DEBUG
    /// For the offscreen renderer's smoke test of the real window.
    var windowForTesting: NSWindow? { window }
    #endif

    func show(tab: SettingsTab = .general, spaceTracker: SpaceTracker, nameManager: SpaceNameManager, preferences: AppPreferences) {
        if window == nil {
            build(spaceTracker: spaceTracker, nameManager: nameManager, preferences: preferences)
        }
        guard let window, let tabController else { return }
        model?.refresh()
        tabController.selectedTabViewItemIndex = tab.rawValue
        resizeWindow(for: tab, animated: false)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build(spaceTracker: SpaceTracker, nameManager: SpaceNameManager, preferences: AppPreferences) {
        let model = SettingsModel(spaceTracker: spaceTracker, nameManager: nameManager, preferences: preferences)
        self.model = model

        let tabController = SettingsTabViewController()
        tabController.tabStyle = .toolbar
        tabController.transitionOptions = []

        func item(_ tab: SettingsTab, _ view: some View) -> NSTabViewItem {
            let controller = NSHostingController(rootView: view.frame(width: Self.width))
            let item = NSTabViewItem(viewController: controller)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            return item
        }
        tabController.addTabViewItem(item(.general, GeneralSettingsView(model: model, spaceTracker: spaceTracker, preferences: preferences)))
        tabController.addTabViewItem(item(.switcher, SwitcherSettingsView(model: model, preferences: preferences)))
        tabController.addTabViewItem(item(.spaces, SpacesSettingsView(nameManager: nameManager, spaceTracker: spaceTracker)))
        tabController.addTabViewItem(item(.about, AboutSettingsView()))
        tabController.onSelectTab = { [weak self] tab in
            self?.resizeWindow(for: tab, animated: self?.window?.isVisible == true)
        }
        self.tabController = tabController

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.window = window
    }

    // MARK: - Sizing

    /// The window height each tab wants. The window resizes between tabs, as is standard.
    private func height(for tab: SettingsTab) -> CGFloat {
        guard let model else { return 480 }
        switch tab {
        case .general:
            let summary = model.summary
            let warnings = (summary.hasUnreachableSpaces || !summary.missingDesktops.isEmpty) ? 1 : 0
            return GeneralSettingsView.height(needsAccessibility: !model.spaceTracker.hasAccessibilityPermission,
                                              shortcutWarnings: warnings, launchError: false)
        case .switcher: return 470
        case .spaces: return SpacesSettingsView.height(spaceCount: model.spaceTracker.spaces.count)
        case .about: return 400
        }
    }

    private func resizeWindow(for tab: SettingsTab, animated: Bool) {
        guard let window else { return }
        window.title = tab.title   // the title follows the selected tab
        let newContent = NSSize(width: Self.width, height: height(for: tab))
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: newContent))
        var origin = window.frame.origin
        origin.y += window.frame.height - frame.height   // keep the top edge in place
        window.setFrame(NSRect(origin: origin, size: frame.size), display: true, animate: animated)
    }
}
