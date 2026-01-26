import SwiftUI

struct MenuBarView: View {
    @ObservedObject var spaceTracker: SpaceTracker
    @ObservedObject var nameManager: SpaceNameManager
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var renamingSpaceIndex: Int?
    @State private var showPermissionHelp = false
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
        }
        .sheet(isPresented: $showPermissionHelp) {
            PermissionHelpView(spaceTracker: spaceTracker, isPresented: $showPermissionHelp)
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
                showPermissionHelp = true
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

                Text(nameManager.name(for: spaceTracker.currentSpaceIndex))
                    .font(.headline)

                Spacer()

                Button(action: { startRenaming(spaceTracker.currentSpaceIndex) }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Rename this space")
            }
        }
    }

    private var spacesList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("All Spaces")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            ForEach(1...max(spaceTracker.totalSpaces, 1), id: \.self) { index in
                spaceRow(for: index)
            }
        }
    }

    private func spaceRow(for index: Int) -> some View {
        let isCurrentSpace = index == spaceTracker.currentSpaceIndex

        return HStack {
            // Active indicator
            Image(systemName: isCurrentSpace ? "circle.fill" : "circle")
                .font(.system(size: 6))
                .foregroundColor(isCurrentSpace ? .blue : .secondary)

            // Name (editable if renaming)
            if isRenaming && renamingSpaceIndex == index {
                TextField("Space name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .rounded))
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        commitRename()
                    }
                    .onExitCommand {
                        cancelRename()
                    }
            } else {
                Text(nameManager.name(for: index))
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(isCurrentSpace ? .primary : .secondary)
            }

            Spacer()

            // Keyboard shortcut hint
            if index <= 9 {
                Text("⌃\(index)")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.5))
            }

            // Rename button
            if !isRenaming {
                Button(action: { startRenaming(index) }) {
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
        .contentShape(Rectangle())
        .onTapGesture {
            handleSpaceTap(index: index)
        }
    }

    private var actionButtons: some View {
        HStack {
            Button(action: openSettings) {
                Label("Settings", systemImage: "gear")
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

    private func handleSpaceTap(index: Int) {
        guard !isRenaming else { return }
        guard index != spaceTracker.currentSpaceIndex else { return }

        if !spaceTracker.hasAccessibilityPermission {
            showPermissionHelp = true
            return
        }

        spaceTracker.switchToSpace(index)
    }

    private func startRenaming(_ index: Int) {
        renamingSpaceIndex = index
        renameText = nameManager.hasCustomName(for: index) ? nameManager.name(for: index) : ""
        isRenaming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }

    private func commitRename() {
        if let index = renamingSpaceIndex {
            nameManager.setName(renameText, for: index)
        }
        isRenaming = false
        renamingSpaceIndex = nil
        renameText = ""
        isTextFieldFocused = false
    }

    private func cancelRename() {
        isRenaming = false
        renamingSpaceIndex = nil
        renameText = ""
        isTextFieldFocused = false
    }

    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Permission Help View

struct PermissionHelpView: View {
    @ObservedObject var spaceTracker: SpaceTracker
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Accessibility Permission Required")
                .font(.headline)

            Text("SpaceStation needs Accessibility permission to switch between Spaces using keyboard shortcuts.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Setup Steps:")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(alignment: .top, spacing: 8) {
                    Text("1.")
                        .fontWeight(.bold)
                    Text("Click 'Open Settings' below")
                }
                .font(.caption)

                HStack(alignment: .top, spacing: 8) {
                    Text("2.")
                        .fontWeight(.bold)
                    Text("Find 'SpaceStation' in the list and enable it")
                }
                .font(.caption)

                HStack(alignment: .top, spacing: 8) {
                    Text("3.")
                        .fontWeight(.bold)
                    Text("Also enable keyboard shortcuts:\nSystem Settings → Keyboard → Keyboard Shortcuts → Mission Control → Enable 'Switch to Desktop 1-9'")
                }
                .font(.caption)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button("Open Settings") {
                    spaceTracker.openAccessibilitySettings()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

#Preview {
    MenuBarView(
        spaceTracker: SpaceTracker(),
        nameManager: SpaceNameManager()
    )
}
