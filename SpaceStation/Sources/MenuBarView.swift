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
                .interactiveDismissDisabled()
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
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)

                Text("Setup Required")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Two quick steps to enable space switching")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Step 1: Accessibility
            SetupStepCard(
                stepNumber: 1,
                icon: "hand.raised.fill",
                iconColor: .orange,
                title: "Accessibility Permission",
                description: "Allow SpaceStation to control your Mac",
                buttonTitle: "Open Accessibility Settings",
                isComplete: spaceTracker.hasAccessibilityPermission
            ) {
                spaceTracker.openAccessibilitySettings()
            }

            // Step 2: Keyboard Shortcuts
            SetupStepCard(
                stepNumber: 2,
                icon: "keyboard.fill",
                iconColor: .purple,
                title: "Enable Keyboard Shortcuts",
                description: "Select Mission Control → Enable \"Switch to Desktop 1-9\"",
                buttonTitle: "Open Keyboard Shortcuts",
                isComplete: false // Can't detect this programmatically
            ) {
                openKeyboardShortcutsSettings()
            }

            Divider()

            // Done button
            Button("Done") {
                spaceTracker.checkAccessibilityPermission()
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 480)
    }

    private func openKeyboardShortcutsSettings() {
        // Open System Settings to Keyboard Shortcuts
        // User then selects "Mission Control" from the left sidebar
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Setup Step Card

struct SetupStepCard: View {
    let stepNumber: Int
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let buttonTitle: String
    let isComplete: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with step number, icon, and title
            HStack(spacing: 10) {
                // Step number / checkmark
                ZStack {
                    Circle()
                        .fill(isComplete ? Color.green : Color.blue)
                        .frame(width: 28, height: 28)

                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(stepNumber)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                // Icon
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)

                // Title
                Text(title)
                    .font(.headline)

                Spacer()
            }

            // Description text - full width, can wrap
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 38)

            // Action button - prominent with press feedback
            Button(action: action) {
                Text(buttonTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(isComplete ? .green : .blue)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isComplete ? Color.green.opacity(0.08) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isComplete ? Color.green.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    MenuBarView(
        spaceTracker: SpaceTracker(),
        nameManager: SpaceNameManager()
    )
}
