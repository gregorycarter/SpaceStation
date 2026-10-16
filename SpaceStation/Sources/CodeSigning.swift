import Foundation
import Security

/// Describes how the running app is signed.
///
/// macOS ties the Accessibility permission to the app's *designated requirement*, a rule
/// derived from its code signature. For an ad-hoc signature (Xcode without a certificate)
/// that rule is a hash of the exact build, so every rebuild looks like a different app. For
/// a certificate-signed build it names the certificate and stays the same across rebuilds.
/// If the requirement changes (ad-hoc to signed, dev certificate to Developer ID, ...) an
/// existing grant stops applying even though System Settings still lists the app as enabled.
enum CodeSigning {
    struct Identity: Equatable {
        let isAdHoc: Bool
        /// The designated requirement as text, e.g. `cdhash H"..."` or
        /// `identifier "..." and anchor apple generic and certificate leaf[...]`.
        let requirement: String?
    }

    enum AccessibilityHint: Equatable {
        /// The app's signing requirement differs from the one that was last granted access.
        case signatureChanged
        /// An ad-hoc build: permission won't survive rebuilds or updates.
        case adHocBuild
    }

    static func isAdHoc(flags: UInt32) -> Bool {
        flags & SecCodeSignatureFlags.adhoc.rawValue != 0
    }

    /// The signing identity of the running process, or nil if it can't be read.
    static func current() -> Identity? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else {
            return nil
        }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0

        var requirement: SecRequirement?
        var requirementText: CFString?
        if SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement {
            SecRequirementCopyString(requirement, [], &requirementText)
        }
        return Identity(isAdHoc: isAdHoc(flags: flags), requirement: requirementText as String?)
    }

    /// Why Accessibility might not be working, when we can tell. Nil when it is granted, or
    /// when nothing about the signature explains it.
    static func accessibilityHint(isTrusted: Bool,
                                  identity: Identity?,
                                  lastTrustedRequirement: String?) -> AccessibilityHint? {
        guard !isTrusted, let identity else { return nil }
        if let last = lastTrustedRequirement, let current = identity.requirement, last != current {
            return .signatureChanged
        }
        return identity.isAdHoc ? .adHocBuild : nil
    }

    /// Whether to automatically clear a stale Accessibility grant: only when the signing
    /// requirement changed since access was granted (so the old grant provably can't apply),
    /// and only once per requirement so a failed attempt can't loop.
    static func shouldAutoResetStaleGrant(hint: AccessibilityHint?,
                                          identity: Identity?,
                                          lastAutoResetRequirement: String?) -> Bool {
        guard hint == .signatureChanged, let requirement = identity?.requirement else { return false }
        return lastAutoResetRequirement != requirement
    }
}
