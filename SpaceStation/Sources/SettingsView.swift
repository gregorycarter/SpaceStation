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
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    // The system (SMAppService) is the source of truth, not a stored preference,
    // so the toggle can't drift if registration fails or the user changes it in
    // System Settings → General → Login Items.
    @State private var launchAtLogin = false
    @State private var launchError: String?

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
