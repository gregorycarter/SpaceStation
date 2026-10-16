import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var nameManager: SpaceNameManager
    @ObservedObject var spaceTracker: SpaceTracker
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        TabView {
            GeneralSettingsView(launchAtLogin: $launchAtLogin)
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
    @Binding var launchAtLogin: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }

                Text("SpaceStation will start automatically when you log in.")
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

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
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
                editingNames[space.id] = newValue
                nameManager.setName(newValue, for: space)
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
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("SpaceStation")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
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
