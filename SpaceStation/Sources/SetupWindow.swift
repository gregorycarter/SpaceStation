import SwiftUI
import AppKit

/// The first-run / permission window: explains the one thing SpaceStation needs (Accessibility, so
/// it can send the shortcuts that switch Spaces) and, optionally, the macOS shortcuts that make
/// switching instant.
@MainActor
final class SetupWindowController {
    static let shared = SetupWindowController()
    private var window: NSWindow?

    private init() {}

    func showSetupWindow(spaceTracker: SpaceTracker) {
        // If the window exists, bring it to the front.
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SetupWindowView(spaceTracker: spaceTracker) { [weak self] in self?.closeWindow() }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 440, height: 420)

        let panel = NSPanel(contentRect: hosting.frame, styleMask: [.titled, .closable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "SpaceStation Setup"
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = panel
    }

    func closeWindow() {
        window?.close()
        window = nil
    }
}

struct SetupWindowView: View {
    @ObservedObject var spaceTracker: SpaceTracker
    let onDone: () -> Void

    // Poll while the window is open: the user is switching on a toggle in System Settings.
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    static func hintText(for hint: CodeSigning.AccessibilityHint) -> String {
        switch hint {
        case .signatureChanged:
            return "This build is signed differently from the one you previously allowed. macOS ties the permission to the app's signature, so SpaceStation may look switched on in System Settings but not count. Click “Reset & Try Again”, then allow it again."
        case .adHocBuild:
            return "This build isn't signed with a developer certificate, so macOS forgets the permission whenever it is rebuilt or updated. If SpaceStation is already switched on but not detected, click “Reset & Try Again”."
        }
    }

    var body: some View {
        let granted = spaceTracker.hasAccessibilityPermission
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                Text(granted ? "You're all set" : "Allow Accessibility")
                    .font(.system(size: 17, weight: .semibold))
                Text(granted
                     ? "SpaceStation can now switch Spaces."
                     : "SpaceStation needs this to send the keyboard shortcuts that switch Spaces.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                step(symbol: "hand.raised.fill", tint: .orange, title: "Accessibility permission",
                     detail: granted ? "Allowed" : "System Settings → Privacy & Security → Accessibility",
                     done: granted) {
                    if !granted {
                        Button("Open Accessibility Settings") { spaceTracker.openAccessibilitySettings() }
                    }
                }

                if !granted {
                    if let hint = spaceTracker.accessibilityHint {
                        Text(Self.hintText(for: hint))
                            .font(.system(size: 12))
                            .foregroundColor(Color(nsColor: .systemOrange))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                    Button("Permission not detected? Reset & Try Again") { spaceTracker.resetAndRequestPermission() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                        .padding(.bottom, 12)
                }

                Divider()

                step(symbol: "keyboard.fill", tint: .purple, title: "Instant switching (optional)",
                     detail: shortcutDetail,
                     done: spaceTracker.hasKeyboardShortcutsEnabled) {
                    if !spaceTracker.hasKeyboardShortcutsEnabled {
                        Button("Open Keyboard Settings") { SystemSettingsPane.keyboardShortcuts.open() }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))

            Button(granted ? "Done" : "Close") {
                spaceTracker.checkAccessibilityPermission()
                onDone()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { spaceTracker.checkAccessibilityPermission() }
        .onReceive(timer) { _ in
            if !spaceTracker.hasAccessibilityPermission { spaceTracker.checkAccessibilityPermission() }
            if !spaceTracker.hasKeyboardShortcutsEnabled { spaceTracker.checkKeyboardShortcuts() }
        }
    }

    private var shortcutDetail: String {
        if spaceTracker.hasKeyboardShortcutsEnabled { return "“Switch to Desktop” shortcuts are on" }
        let missing = SpaceListFormat.describe(spaceTracker.missingShortcuts)
        return "\(missing) can only be reached by stepping, which is slower. Turn on “Switch to Desktop” under Mission Control."
    }

    private func step<Actions: View>(symbol: String, tint: Color, title: String, detail: String, done: Bool,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : tint.opacity(0.9)).frame(width: 30, height: 30)
                Image(systemName: done ? "checkmark" : symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions().padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
