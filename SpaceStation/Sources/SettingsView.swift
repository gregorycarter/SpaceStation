import SwiftUI
import ServiceManagement
import os.log

struct SettingsView: View {
    @ObservedObject var nameManager: SpaceNameManager
    @ObservedObject var spaceTracker: SpaceTracker

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            SpaceNamesSettingsView(nameManager: nameManager, spaceTracker: spaceTracker)
                .tabItem {
                    Label("Space Names", systemImage: "square.grid.2x2")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 460)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    // The system (SMAppService) is the source of truth, not a stored preference,
    // so the toggle can't drift if registration fails or the user changes it in
    // System Settings → General → Login Items.
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var switcherHotCorner = HotCorner(
        rawValue: UserDefaults.standard.string(forKey: SwitcherController.hotCornerKey) ?? "") ?? .off
    @State private var switcherHotKeyEnabled = UserDefaults.standard.object(forKey: SwitcherController.hotKeyEnabledKey) as? Bool ?? true

    private static let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "Settings")

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))

                Text("SpaceStation will start automatically when you log in.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section {
                Toggle("Show Space switcher with ⌃S", isOn: Binding(
                    get: { switcherHotKeyEnabled },
                    set: { newValue in
                        switcherHotKeyEnabled = newValue
                        UserDefaults.standard.set(newValue, forKey: SwitcherController.hotKeyEnabledKey)
                        SwitcherController.shared.applyHotKeyPreference()
                    }
                ))

                Text("A floating strip of your named Spaces. Pick one with the mouse, 1–9, or ←/→ and Return. You can also open it from the menu.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Open from a screen corner", selection: Binding(
                    get: { switcherHotCorner },
                    set: { newValue in
                        switcherHotCorner = newValue
                        UserDefaults.standard.set(newValue.rawValue, forKey: SwitcherController.hotCornerKey)
                        SwitcherController.shared.applyHotCornerPreference()
                    }
                )) {
                    ForEach(HotCorner.allCases) { corner in
                        Text(corner.label).tag(corner)
                    }
                }

                Text("Rest the pointer in the corner for a moment. If macOS Hot Corners (System Settings → Desktop & Dock) use the same corner, both will fire, so pick a corner they don't use.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Text("Keyboard Shortcuts")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow("Switch to Space 1-9", shortcut: "⌃1 - ⌃9")
                    shortcutRow("Open Mission Control", shortcut: "⌃↑")
                }
                .padding(.top, 4)

                Text("These are system shortcuts. Configure them in System Settings → Keyboard → Shortcuts → Mission Control.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            refreshLaunchAtLogin()
        }
    }

    private func shortcutRow(_ label: String, shortcut: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
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

// MARK: - Space Names Settings

struct SpaceNamesSettingsView: View {
    @ObservedObject var nameManager: SpaceNameManager
    @ObservedObject var spaceTracker: SpaceTracker
    @State private var editingNames: [String: String] = [:]
    @State private var iconPickerSpaceID: String?

    var body: some View {
        Form {
            Section {
                Text("Customize the names for your Spaces. Leave blank to use the default name.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Space Names") {
                ForEach(spaceTracker.spaces) { space in
                    HStack {
                        Button(action: { iconPickerSpaceID = space.id }) {
                            SpaceIconView(icon: nameManager.icon(for: space) ?? .symbol("desktopcomputer"), size: 22)
                        }
                        .buttonStyle(.plain)
                        .help("Choose an icon")
                        .popover(isPresented: Binding(
                            get: { iconPickerSpaceID == space.id },
                            set: { if !$0 { iconPickerSpaceID = nil } }
                        )) {
                            IconPickerView(current: nameManager.icon(for: space) ?? .symbol("desktopcomputer")) { icon in
                                nameManager.setIcon(icon, for: space)
                                iconPickerSpaceID = nil
                            }
                        }

                        Text("Desktop \(space.index)")
                            .frame(width: 80, alignment: .leading)
                            .foregroundColor(.secondary)

                        Image(systemName: "arrow.right")
                            .foregroundColor(.gray.opacity(0.5))

                        TextField(
                            "Desktop \(space.index)",
                            text: binding(for: space)
                        )
                        .textFieldStyle(.roundedBorder)

                        if nameManager.hasCustomName(for: space) {
                            Button(action: { clearName(space) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear custom name")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            nameManager.migrateLegacyNames(using: spaceTracker.spaces)
            loadCurrentNames()
        }
    }

    private func binding(for space: SpaceInfo) -> Binding<String> {
        Binding(
            get: { editingNames[space.id] ?? nameManager.name(for: space) },
            set: { newValue in
                let limited = String(newValue.prefix(SpaceNameManager.maxNameLength))
                editingNames[space.id] = limited
                nameManager.setName(limited, for: space)
            }
        )
    }

    private func loadCurrentNames() {
        for space in spaceTracker.spaces where nameManager.hasCustomName(for: space) {
            editingNames[space.id] = nameManager.name(for: space)
        }
    }

    private func clearName(_ space: SpaceInfo) {
        editingNames.removeValue(forKey: space.id)
        nameManager.removeName(for: space)
    }
}

// MARK: - Icon Picker

struct IconPickerView: View {
    let current: SpaceIcon
    /// Called with the chosen icon, or nil to reset to the default.
    let onSelect: (SpaceIcon?) -> Void

    @State private var emojiText = ""

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(SpaceIcon.symbolChoices, id: \.self) { name in
                    let icon = SpaceIcon.symbol(name)
                    Button(action: { onSelect(icon) }) {
                        SpaceIconView(icon: icon, size: 22)
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(icon == current ? Color.accentColor.opacity(0.25) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                }
            }

            Divider()

            HStack {
                TextField("Emoji", text: $emojiText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit(applyEmoji)
                Button("Use emoji", action: applyEmoji)
                    .disabled(SpaceIcon.emoji(from: emojiText) == nil)
                Spacer()
                Button("Reset") { onSelect(nil) }
            }
        }
        .padding(14)
        .frame(width: 270)
    }

    private func applyEmoji() {
        if let icon = SpaceIcon.emoji(from: emojiText) {
            onSelect(icon)
        }
    }
}

// MARK: - About View

struct AboutView: View {
    private static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("SpaceStation")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(Self.versionString)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("A menu bar app for naming and managing your macOS Spaces.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()

            VStack(spacing: 4) {
                Text("Developed by Gregory Carter")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link("www.gregorycarter.net", destination: URL(string: "https://www.gregorycarter.net")!)
                    .font(.caption)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView(nameManager: SpaceNameManager(), spaceTracker: SpaceTracker())
}
