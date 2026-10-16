import AppKit
import ApplicationServices
import Combine
import os.log

/// Owns Accessibility permission checks, signing history, and recovery from a stale grant.
@MainActor
final class AccessibilityController: ObservableObject {
    struct System {
        var identity: @MainActor () -> CodeSigning.Identity?
        var isTrusted: @MainActor (_ prompt: Bool) -> Bool
        var reset: @MainActor () async throws -> Void
        var sleep: @MainActor (UInt64) async -> Void
        var openSettings: @MainActor () -> Void

        static let live = System(
            identity: CodeSigning.current,
            isTrusted: { prompt in
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
                return AXIsProcessTrustedWithOptions(options)
            },
            reset: {
                let bundleID = Bundle.main.bundleIdentifier ?? "com.gregorycarter.SpaceStation"
                try await Task.detached {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                    task.arguments = ["reset", "Accessibility", bundleID]
                    try task.run()
                    task.waitUntilExit()
                }.value
            },
            sleep: { try? await Task.sleep(nanoseconds: $0) },
            openSettings: {
                // Preserve the existing single URL and failure behavior.
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            })
    }

    @Published private(set) var isTrusted = false
    @Published private(set) var hint: CodeSigning.AccessibilityHint?

    private let defaults: UserDefaults
    private let system: System
    private let identity: CodeSigning.Identity?
    private var observer: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.gregorycarter.SpaceStation", category: "Accessibility")
    static let lastTrustedRequirementKey = "lastAccessibilityTrustedRequirement"
    static let lastAutoResetRequirementKey = "lastAccessibilityAutoResetRequirement"

    init(defaults: UserDefaults = .standard, system: System? = nil) {
        let system = system ?? .live
        self.defaults = defaults
        self.system = system
        identity = system.identity()
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    func startMonitoring() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The trust database updates just after the notification arrives.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                Task { @MainActor in self?.check() }
            }
        }
        // Never reset macOS permissions from a test process.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        healStaleGrantIfNeeded()
    }

    func healStaleGrantIfNeeded() {
        guard CodeSigning.shouldAutoResetStaleGrant(
            hint: hint, identity: identity,
            lastAutoResetRequirement: defaults.string(forKey: Self.lastAutoResetRequirementKey)),
              let requirement = identity?.requirement else { return }
        defaults.set(requirement, forKey: Self.lastAutoResetRequirementKey)
        logger.info("Stale Accessibility grant for a previous signature; resetting it once")
        resetAndRequest(openSettings: false)
    }

    func check() {
        update(trusted: system.isTrusted(false))
        logger.info("Accessibility permission check: \(self.isTrusted)")
    }

    func request() {
        update(trusted: system.isTrusted(true))
        logger.info("Accessibility permission after request: \(self.isTrusted)")
    }

    func openSettings() {
        // Prompt to add the app to the list; the existing flow refreshes state on its next check.
        _ = system.isTrusted(true)
        system.openSettings()
    }

    @discardableResult
    func resetAndRequest(openSettings: Bool = true) -> Task<Void, Never> {
        let system = self.system
        let logger = self.logger
        return Task { [weak self] in
            do { try await system.reset() }
            catch { logger.error("tccutil failed: \(error.localizedDescription)") }
            await system.sleep(500_000_000)
            guard let self else { return }
            self.request()
            if openSettings { system.openSettings() }
        }
    }

    private func update(trusted: Bool) {
        isTrusted = trusted
        if trusted, let requirement = identity?.requirement {
            defaults.set(requirement, forKey: Self.lastTrustedRequirementKey)
        }
        hint = CodeSigning.accessibilityHint(
            isTrusted: trusted, identity: identity,
            lastTrustedRequirement: defaults.string(forKey: Self.lastTrustedRequirementKey))
    }
}

extension CodeSigning.AccessibilityHint {
    var explanation: String {
        switch self {
        case .signatureChanged:
            return "This build is signed differently from the one you previously allowed. macOS ties the permission to the app's signature, so SpaceStation may look switched on in System Settings but not count. Click “Reset & Try Again”, then allow it again."
        case .adHocBuild:
            return "This build isn't signed with a developer certificate, so macOS forgets the permission whenever it is rebuilt or updated. If SpaceStation is already switched on but not detected, click “Reset & Try Again”."
        }
    }
}
