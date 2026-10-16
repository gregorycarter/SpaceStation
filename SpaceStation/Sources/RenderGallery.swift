#if DEBUG
import SwiftUI
import AppKit

/// Debug-only: renders the app's views to PNG files offscreen, so the layout can be checked in
/// light and dark mode without opening any windows. Run the app with SPACESTATION_RENDER_DIR set
/// to the output folder; it exits when done and installs no menu bar item, hotkey or hot corner.
@MainActor
enum RenderGallery {
    static func run(directory: String) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Real Space IDs from this Mac, with sample names and icons like the design's.
        let suite = "SpaceStationRender-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = SpaceTracker()
        let names = SpaceNameManager(defaults: defaults)
        let prefs = AppPreferences(defaults: defaults)
        prefs.hotCorner = .topRight
        sampleData(tracker: tracker, names: names)
        let model = SettingsModel(spaceTracker: tracker, nameManager: names, preferences: prefs)
        // A fake update check (no network) that reports a newer release, to render that state.
        let updates = UpdateChecker(currentVersion: "1.0.0", defaults: defaults, fetch: { _ in
            let body = try JSONSerialization.data(withJSONObject: [
                "tag_name": "v1.1.0", "html_url": "https://github.com/gregorycarter/SpaceStation/releases/tag/v1.1.0"])
            return (body, HTTPURLResponse(url: UpdateChecker.latestReleaseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        Task { @MainActor in _ = await updates.check() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        for dark in [false, true] {
            let tag = dark ? "dark" : "light"
            let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
            let panelBackground = dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.965, alpha: 1)
            let windowBackground = dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.925, alpha: 1)

            // Switcher: this Mac's Spaces, and a 16-Space case with long names.
            let items7 = tracker.spaces.map { SwitcherItem(space: $0, name: names.name(for: $0), icon: names.icon(for: $0)) }
            let m7 = SwitcherModel()
            m7.items = items7
            m7.currentID = items7.indices.contains(2) ? items7[2].id : nil
            m7.selectedIndex = 3
            render(SwitcherView(model: m7) { _ in },
                   size: CGSize(width: SwitcherLayout.panelWidth(count: items7.count, cardWidth: 112),
                                height: SwitcherLayout.panelHeight(count: items7.count, showsFooter: true)),
                   appearance: appearance, background: panelBackground, to: folder.appendingPathComponent("switcher-\(items7.count)-\(tag).png"))

            let m16 = SwitcherModel()
            m16.items = sample16()
            m16.currentID = m16.items[2].id
            m16.selectedIndex = 7
            render(SwitcherView(model: m16) { _ in },
                   size: CGSize(width: SwitcherLayout.panelWidth(count: 16, cardWidth: 112),
                                height: SwitcherLayout.panelHeight(count: 16, showsFooter: true)),
                   appearance: appearance, background: panelBackground, to: folder.appendingPathComponent("switcher-16-\(tag).png"))

            // The rename popover (Recruitment, as in the design).
            let recruit = tracker.spaces.indices.contains(4) ? tracker.spaces[4] : tracker.spaces[0]
            render(RenameView(space: recruit, name: "Recruitment", icon: .symbol("person.2"),
                              onRename: { _ in }, onCancel: {}, onOpenCharacterPalette: {}),
                   size: CGSize(width: 316, height: 292), appearance: appearance,
                   background: dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.95, alpha: 1),
                   to: folder.appendingPathComponent("rename-\(tag).png"))

            render(SetupWindowView(spaceTracker: tracker, onDone: {}), size: CGSize(width: 440, height: 440),
                   appearance: appearance, background: windowBackground,
                   to: folder.appendingPathComponent("setup-\(tag).png"))

            // Settings tabs at the heights the window uses.
            let w = SettingsWindowController.width
            render(GeneralSettingsView(model: model, spaceTracker: tracker, preferences: prefs),
                   size: CGSize(width: w, height: 700), appearance: appearance, background: windowBackground,
                   to: folder.appendingPathComponent("settings-general-\(tag).png"))
            render(SwitcherSettingsView(model: model, preferences: prefs),
                   size: CGSize(width: w, height: 470), appearance: appearance, background: windowBackground,
                   to: folder.appendingPathComponent("settings-switcher-\(tag).png"))
            render(SpacesSettingsView(nameManager: names, spaceTracker: tracker),
                   size: CGSize(width: w, height: SpacesSettingsView.height(spaceCount: tracker.spaces.count)),
                   appearance: appearance, background: windowBackground,
                   to: folder.appendingPathComponent("settings-spaces-\(tag).png"))
            render(AboutSettingsView(updateChecker: updates), size: CGSize(width: w, height: 440), appearance: appearance, background: windowBackground,
                   to: folder.appendingPathComponent("settings-about-\(tag).png"))
        }
        // Smoke test of the real Settings window (this is the code path that once crashed on
        // building the tab controller): open every tab, check it, and capture the window chrome.
        for tab in SettingsTab.allCases {
            SettingsWindowController.shared.show(tab: tab, spaceTracker: tracker, nameManager: names, preferences: prefs, updateChecker: updates)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            guard let window = SettingsWindowController.shared.windowForTesting, let frameView = window.contentView?.superview else {
                print("FAILED: no Settings window for \(tab.title)")
                continue
            }
            print("Settings tab \(tab.title): window title '\(window.title)', content \(Int(window.contentLayoutRect.width))x\(Int(window.contentLayoutRect.height))")
            if let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
                frameView.cacheDisplay(in: frameView.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("window-\(tab.title.lowercased()).png"))
            }
        }
        print("Rendered to \(folder.path)")
    }

    private static func sampleData(tracker: SpaceTracker, names: SpaceNameManager) {
        let samples: [(String, SpaceIcon?)] = [
            ("Inbox", .symbol("tray")), ("Terminal", .symbol("terminal")), ("Kasb", .emoji("🛰️")),
            ("Personal Finance", .symbol("creditcard")), ("Recruitment", .symbol("person.2")),
            ("Knightian", .emoji("🧭")), ("", nil),
        ]
        for (space, sample) in zip(tracker.spaces, samples) {
            names.setName(sample.0, for: space)
            names.setIcon(sample.1, for: space)
        }
    }

    private static func sample16() -> [SwitcherItem] {
        let data: [(String, SpaceIcon?)] = [
            ("Inbox", .symbol("tray")), ("Terminal", .symbol("terminal")), ("Kasb", .emoji("🛰️")),
            ("Personal Finance", .symbol("creditcard")), ("Recruitment", .symbol("person.2")), ("Knightian", .emoji("🧭")),
            ("Desktop 7", nil), ("Quarterly Planning", .symbol("briefcase")), ("Music", .emoji("🎧")),
            ("Design", .symbol("paintpalette")), ("Reading List", .symbol("book")), ("Client — Northwind", .symbol("calendar")),
            ("Mail", .symbol("envelope")), ("Calendar", .symbol("calendar")), ("Video Edit", .emoji("🎬")), ("Desktop 16", nil),
        ]
        return data.enumerated().map { offset, entry in
            SwitcherItem(space: SpaceInfo(id: "sample-\(offset)", index: offset + 1), name: entry.0, icon: entry.1)
        }
    }

    /// Renders `view` at `size` (points) into a 2x PNG.
    private static func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, background: NSColor, to url: URL) {
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = background.cgColor
        let host = NSHostingView(rootView: view)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first layout pass.
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        container.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        container.cacheDisplay(in: container.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}
#endif
