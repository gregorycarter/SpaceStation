import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var nameManager: SpaceNameManager
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        TabView {
            GeneralSettingsView(launchAtLogin: $launchAtLogin)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            SpaceNamesSettingsView(nameManager: nameManager)
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
                    .onChange(of: launchAtLogin) { _, newValue in
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
    @State private var editingNames: [Int: String] = [:]

    var body: some View {
        Form {
            Section {
                Text("Customize the names for your Spaces. Leave blank to use the default name.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Space Names") {
                ForEach(1...9, id: \.self) { index in
                    HStack {
                        Text("Desktop \(index)")
                            .frame(width: 80, alignment: .leading)
                            .foregroundColor(.secondary)

                        Image(systemName: "arrow.right")
                            .foregroundColor(.tertiary)

                        TextField(
                            "Desktop \(index)",
                            text: binding(for: index)
                        )
                        .textFieldStyle(.roundedBorder)

                        if nameManager.hasCustomName(for: index) {
                            Button(action: { clearName(index) }) {
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
            loadCurrentNames()
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { editingNames[index] ?? nameManager.name(for: index) },
            set: { newValue in
                editingNames[index] = newValue
                nameManager.setName(newValue, for: index)
            }
        )
    }

    private func loadCurrentNames() {
        for index in 1...9 {
            if nameManager.hasCustomName(for: index) {
                editingNames[index] = nameManager.name(for: index)
            }
        }
    }

    private func clearName(_ index: Int) {
        editingNames.removeValue(forKey: index)
        nameManager.removeName(for: index)
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

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

            Link("View on GitHub", destination: URL(string: "https://github.com/gregorycarter/SpaceStation")!)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView(nameManager: SpaceNameManager())
}
