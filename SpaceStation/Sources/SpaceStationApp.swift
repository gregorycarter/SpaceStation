import SwiftUI

@main
struct SpaceStationApp: App {
    @StateObject private var spaceTracker = SpaceTracker()
    @StateObject private var nameManager = SpaceNameManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(spaceTracker: spaceTracker, nameManager: nameManager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.2x2")
                Text(spaceTracker.isInFullscreenSpace ? "Full Screen" : nameManager.name(for: spaceTracker.currentSpace))
                    .font(.system(.body, design: .rounded))
                    .lineLimit(1)
            }
            .onReceive(spaceTracker.$spaces) { spaces in
                nameManager.migrateLegacyNames(using: spaces)
            }
            .onAppear {
                SwitcherController.shared.configure(spaceTracker: spaceTracker, nameManager: nameManager)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Settings Window Controller

/// Opens the Settings window directly. SwiftUI's Settings scene / SettingsLink is unreliable
/// in menu-bar-only apps (no Dock icon), so this uses a plain NSWindow, like the setup window.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private init() {}

    func show(nameManager: SpaceNameManager, spaceTracker: SpaceTracker) {
        if window == nil {
            let hostingView = NSHostingView(rootView: SettingsView(nameManager: nameManager, spaceTracker: spaceTracker))
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "SpaceStation Settings"
            newWindow.contentView = hostingView
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }

        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Setup Window Controller

@MainActor
class SetupWindowController {
    static let shared = SetupWindowController()
    private var window: NSWindow?

    private init() {}

    func showSetupWindow(spaceTracker: SpaceTracker) {
        // If window exists, bring to front
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window
        let setupView = SetupWindowView(spaceTracker: spaceTracker) { [weak self] in
            self?.closeWindow()
        }

        let hostingView = NSHostingView(rootView: setupView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 400)

        let newWindow = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "SpaceStation Setup"
        newWindow.contentView = hostingView
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.level = .floating
        newWindow.isMovableByWindowBackground = true

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    /// Switch to a Space, or walk the user through setup if that isn't possible yet
    /// (no Accessibility permission, or the Desktop shortcut is disabled).
    func switchOrShowSetup(spaceTracker: SpaceTracker, to index: Int) {
        guard index <= SpaceTracker.maxSwitchableSpace else { return }
        if !spaceTracker.hasAccessibilityPermission || !spaceTracker.switchToSpace(index) {
            showSetupWindow(spaceTracker: spaceTracker)
        }
    }

    func closeWindow() {
        window?.close()
        window = nil
    }
}

// MARK: - Setup Window View (Standalone)

struct SetupWindowView: View {
    /// e.g. "Select Mission Control → turn on “Switch to Desktop 7”"
    static func shortcutInstruction(missing: [Int]) -> String {
        let desktops = missing.map(String.init).joined(separator: ", ")
        return "Select Mission Control → turn on “Switch to Desktop \(desktops)”"
    }

    static func hintText(for hint: CodeSigning.AccessibilityHint) -> String {
        switch hint {
        case .buildChanged:
            return "This is a different build from the one you previously allowed. macOS ties the permission to the exact build, so SpaceStation may look switched on in System Settings but not count. Click “Reset & try again” below, then allow it again."
        case .adHocBuild:
            return "This build isn't signed with a developer certificate, so macOS forgets the permission whenever it is rebuilt or updated. If SpaceStation is already switched on but not detected, click “Reset & try again” below."
        }
    }

    @ObservedObject var spaceTracker: SpaceTracker
    let onDone: () -> Void

    // Timer to poll permission status
    let permissionTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                Text(spaceTracker.hasAccessibilityPermission && spaceTracker.hasKeyboardShortcutsEnabled
                    ? "Ready!"
                    : spaceTracker.hasAccessibilityPermission
                        ? "Almost Ready!"
                        : "Setup Required")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(spaceTracker.hasAccessibilityPermission && spaceTracker.hasKeyboardShortcutsEnabled
                    ? "You're all set to use SpaceStation"
                    : spaceTracker.hasAccessibilityPermission
                        ? "Just one more step to enable space switching"
                        : "Two quick steps to enable space switching")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Step 1: Accessibility
            VStack(spacing: 8) {
                SetupStepCardStandalone(
                    stepNumber: 1,
                    icon: "hand.raised.fill",
                    iconColor: .orange,
                    title: "Accessibility Permission",
                    description: spaceTracker.hasAccessibilityPermission
                        ? "Permission granted"
                        : "Allow SpaceStation to control your Mac",
                    buttonTitle: "Open Accessibility Settings",
                    isComplete: spaceTracker.hasAccessibilityPermission
                ) {
                    spaceTracker.openAccessibilitySettings()
                }

                // Explain a stale grant, which is common with unsigned/ad-hoc builds
                if !spaceTracker.hasAccessibilityPermission, let hint = spaceTracker.accessibilityHint {
                    Text(Self.hintText(for: hint))
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                // Show reset option if permission appears stuck
                if !spaceTracker.hasAccessibilityPermission {
                    Button(action: {
                        spaceTracker.resetAndRequestPermission()
                    }) {
                        Text("Permission not detected? Reset & try again")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Step 2: Keyboard Shortcuts
            SetupStepCardStandalone(
                stepNumber: 2,
                icon: "keyboard.fill",
                iconColor: .purple,
                title: "Enable Keyboard Shortcuts",
                description: spaceTracker.hasKeyboardShortcutsEnabled
                    ? "Keyboard shortcuts enabled"
                    : Self.shortcutInstruction(missing: spaceTracker.missingShortcuts),
                buttonTitle: "Open Keyboard Shortcuts",
                isComplete: spaceTracker.hasKeyboardShortcutsEnabled
            ) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            // Done button
            Button("Done") {
                spaceTracker.checkAccessibilityPermission()
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            // Refresh permission status when view appears
            spaceTracker.checkAccessibilityPermission()
        }
        .onReceive(permissionTimer) { _ in
            // Poll while either permission is not yet granted
            if !spaceTracker.hasAccessibilityPermission {
                spaceTracker.checkAccessibilityPermission()
            }
            if !spaceTracker.hasKeyboardShortcutsEnabled {
                spaceTracker.checkKeyboardShortcuts()
            }
        }
    }
}

// MARK: - Setup Step Card (Standalone version)

struct SetupStepCardStandalone: View {
    let stepNumber: Int
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let buttonTitle: String
    let isComplete: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
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

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.headline)

                Spacer()
            }

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 38)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(isComplete ? .green : .blue)
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
