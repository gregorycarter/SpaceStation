import SwiftUI

struct SwitcherSettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        Form {
            Section {
                SettingsRow(label: "Keyboard shortcut") {
                    ShortcutRecorderControl(shortcut: $preferences.switcherShortcut)
                }

                SettingsRow(label: "Hot corner", minHeight: 62) {
                    HStack(spacing: 12) {
                        CornerMapView(selected: preferences.hotCorner, inUse: model.usedCorners) { preferences.hotCorner = $0 }
                        Picker("Hot corner", selection: $preferences.hotCorner) {
                            ForEach(HotCorner.allCases) { corner in
                                Text(corner.label).tag(corner)
                                    .disabled(model.usedCorners[corner] != nil && corner != preferences.hotCorner)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                }

                SettingsRow(label: "Delay") {
                    HStack(spacing: 8) {
                        Text("Instant").font(.system(size: 11)).foregroundColor(.secondary)
                        Slider(value: $preferences.hotCornerDelay, in: AppPreferences.delayRange)
                            .frame(width: 180)
                            .accessibilityLabel("Hot corner delay")
                        Text("Long").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .disabled(preferences.hotCorner == .off)

                SettingsRow(label: "Open the panel") {
                    Picker("Open the panel", selection: $preferences.panelPlacement) {
                        ForEach(PanelPlacement.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            } footer: {
                footer
            }

            Section {
                Toggle("Show keyboard hints", isOn: $preferences.showKeyboardHints)
                Toggle("Close when the pointer leaves", isOn: $preferences.closeOnPointerExit)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refresh() }
    }

    /// Explains conflicts instead of leaving them to be discovered: the chosen shortcut or corner
    /// already used by macOS, or corners that can't be offered.
    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let conflict = model.shortcutConflict, let shortcut = preferences.switcherShortcut {
                warning("\(shortcut.display) is also used by macOS (\(conflict)), so both will react.")
            }
            if let action = model.usedCorners[preferences.hotCorner], preferences.hotCorner != .off {
                warning("\(preferences.hotCorner.label) is also used by macOS Hot Corners (\(action)), so both will act.")
                desktopAndDockLink
            } else if let (corner, action) = model.usedCorners.sorted(by: { $0.key.rawValue < $1.key.rawValue }).first {
                HStack(spacing: 4) {
                    Text("\(corner.label) is unavailable because \(action) uses it.")
                    desktopAndDockLink
                }
            }
            if model.shortcutConflict == nil, model.usedCorners[preferences.hotCorner] == nil, model.usedCorners.isEmpty {
                Text("Rest the pointer in the corner to open the switcher.")
            }
        }
        .settingsFooter()
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Color(nsColor: .systemYellow))
            Text(text)
        }
    }

    private var desktopAndDockLink: some View {
        Button("Desktop & Dock Settings…") { SystemSettingsPane.desktopAndDock.open() }
            .buttonStyle(.link)
    }
}
