import SwiftUI

struct MenuBarView: View {
    @ObservedObject var spaceTracker: SpaceTracker
    @ObservedObject var nameManager: SpaceNameManager
    @State private var renameText = ""
    @State private var renamingSpace: SpaceInfo?
    private var isRenaming: Bool { renamingSpace != nil }
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Permission warning banner
            if !spaceTracker.hasAccessibilityPermission {
                permissionBanner
                Divider()
                    .padding(.vertical, 4)
            }

            // Header showing current space
            currentSpaceHeader

            Divider()
                .padding(.vertical, 8)

            // List of all spaces
            spacesList

            Divider()
                .padding(.vertical, 8)

            // Actions
            actionButtons
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            spaceTracker.checkAccessibilityPermission()
            nameManager.migrateLegacyNames(using: spaceTracker.spaces)
        }
    }

    // MARK: - Permission Banner

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Permission Required")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Click to enable space switching")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Enable") {
                SetupWindowController.shared.showSetupWindow(spaceTracker: spaceTracker)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Subviews

    private var currentSpaceHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Current Space")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !spaceTracker.isTrackingAvailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .help("Space tracking unavailable")
                }
            }

            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)

                if spaceTracker.isInFullscreenSpace {
                    Text("Full Screen")
                        .font(.headline)

                    Spacer()
                } else {
                    Text(nameManager.name(for: spaceTracker.currentSpace))
                        .font(.headline)

                    Spacer()

                    Button(action: { startRenaming(spaceTracker.currentSpace) }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rename this space")
                }
            }
        }
    }

    private var spacesList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("All Spaces")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            ForEach(spaceTracker.spaces) { space in
                spaceRow(for: space)
            }
        }
    }

    private func spaceRow(for space: SpaceInfo) -> some View {
        let index = space.index
        let canSwitch = index <= SpaceTracker.maxSwitchableSpace
        let isCurrentSpace = !spaceTracker.isInFullscreenSpace && index == spaceTracker.currentSpaceIndex

        return HStack {
            // Main tappable area - switches to this space
            Button(action: { handleSpaceTap(space) }) {
                HStack {
                    // Active indicator
                    Image(systemName: isCurrentSpace ? "circle.fill" : "circle")
                        .font(.system(size: 6))
                        .foregroundColor(isCurrentSpace ? .blue : .secondary)

                    // Name (editable if renaming)
                    if isRenaming && renamingSpace?.id == space.id {
                        TextField("Space name", text: $renameText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: renameText) { newValue in
                                if newValue.count > SpaceNameManager.maxNameLength {
                                    renameText = String(newValue.prefix(SpaceNameManager.maxNameLength))
                                }
                            }
                            .font(.system(.body, design: .rounded))
                            .focused($isTextFieldFocused)
                            .onSubmit {
                                commitRename()
                            }
                            .onExitCommand {
                                cancelRename()
                            }
                    } else {
                        Text(nameManager.name(for: space))
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(isCurrentSpace ? .primary : .secondary)
                    }

                    Spacer()

                    // Keyboard shortcut hint (macOS only offers shortcuts for Desktops 1-9)
                    if canSwitch {
                        Text("⌃\(index)")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSwitch && !isCurrentSpace)
            .help(canSwitch ? "" : "macOS has no keyboard shortcut for Desktop \(index), so SpaceStation can't switch to it")

            // Rename button (separate from main tap area)
            if !isRenaming {
                Button(action: { startRenaming(space) }) {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .opacity(0.6)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrentSpace ? Color.blue.opacity(0.1) : Color.clear)
        )
    }

    private var actionButtons: some View {
        HStack {
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                })
            } else {
                Button(action: openSettings) {
                    Label("Settings", systemImage: "gear")
                }
            }

            Spacer()

            if isRenaming {
                Button("Done") {
                    commitRename()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button(action: quitApp) {
                    Label("Quit", systemImage: "power")
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
    }

    // MARK: - Actions

    private func handleSpaceTap(_ space: SpaceInfo) {
        let index = space.index
        guard !isRenaming else { return }
        guard spaceTracker.isInFullscreenSpace || index != spaceTracker.currentSpaceIndex else { return }

        guard index <= SpaceTracker.maxSwitchableSpace else { return }

        // switchToSpace returns false when Accessibility or the Desktop shortcut
        // isn't set up; walk the user through setup instead of failing silently.
        if !spaceTracker.hasAccessibilityPermission || !spaceTracker.switchToSpace(index) {
            SetupWindowController.shared.showSetupWindow(spaceTracker: spaceTracker)
        }
    }

    private func startRenaming(_ space: SpaceInfo) {
        renamingSpace = space
        renameText = nameManager.hasCustomName(for: space) ? nameManager.name(for: space) : ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }

    private func commitRename() {
        if let space = renamingSpace {
            nameManager.setName(renameText, for: space)
        }
        renamingSpace = nil
        renameText = ""
        isTextFieldFocused = false
    }

    private func cancelRename() {
        renamingSpace = nil
        renameText = ""
        isTextFieldFocused = false
    }

    private func openSettings() {
        // Bring app to front and open settings (macOS 13 fallback; macOS 14+ uses SettingsLink).
        // Ventura renamed the responder action from showPreferencesWindow: to showSettingsWindow:.
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

#Preview {
    MenuBarView(
        spaceTracker: SpaceTracker(),
        nameManager: SpaceNameManager()
    )
}
