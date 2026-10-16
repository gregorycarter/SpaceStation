import Foundation
import Security

/// Describes how the running app is signed.
///
/// macOS ties the Accessibility permission to the app's code signature. An ad-hoc
/// signature (what Xcode produces without a signing certificate) is identified only by
/// a hash of that exact build, so every rebuild looks like a different app and the
/// previously granted permission stops applying, even though System Settings still
/// lists SpaceStation as switched on.
enum CodeSigning {
    struct Identity: Equatable {
        let isAdHoc: Bool
        /// Hex hash of this exact build (the cdhash), if available.
        let buildID: String?
    }

    enum AccessibilityHint: Equatable {
        /// An ad-hoc build whose hash differs from the one that was last granted access.
        case buildChanged
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
        let unique = dict[kSecCodeInfoUnique as String] as? Data
        return Identity(isAdHoc: isAdHoc(flags: flags),
                        buildID: unique?.map { String(format: "%02x", $0) }.joined())
    }

    /// Why Accessibility might not be working, when we can tell. Nil when it is granted,
    /// or when the signature gives no reason to suspect a stale grant.
    static func accessibilityHint(isTrusted: Bool,
                                  identity: Identity?,
                                  lastTrustedBuildID: String?) -> AccessibilityHint? {
        guard !isTrusted, let identity, identity.isAdHoc else { return nil }
        if let last = lastTrustedBuildID, let current = identity.buildID, last != current {
            return .buildChanged
        }
        return .adHocBuild
    }
}
