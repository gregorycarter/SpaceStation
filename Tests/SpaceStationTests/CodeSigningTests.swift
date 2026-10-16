import XCTest
import Security
@testable import SpaceStation

final class CodeSigningTests: XCTestCase {
    private let adHoc = CodeSigning.Identity(isAdHoc: true, buildID: "bbbb")
    private let signed = CodeSigning.Identity(isAdHoc: false, buildID: "bbbb")

    func testAdHocFlagIsDetected() {
        XCTAssertTrue(CodeSigning.isAdHoc(flags: SecCodeSignatureFlags.adhoc.rawValue))
        XCTAssertTrue(CodeSigning.isAdHoc(flags: SecCodeSignatureFlags.adhoc.rawValue | 0x10000))
        XCTAssertFalse(CodeSigning.isAdHoc(flags: 0x10000)) // e.g. runtime flag only
        XCTAssertFalse(CodeSigning.isAdHoc(flags: 0))
    }

    func testNoHintWhenTrusted() {
        XCTAssertNil(CodeSigning.accessibilityHint(isTrusted: true, identity: adHoc, lastTrustedBuildID: "aaaa"))
    }

    func testBuildChangedWhenAdHocBuildDiffersFromLastTrusted() {
        XCTAssertEqual(CodeSigning.accessibilityHint(isTrusted: false, identity: adHoc, lastTrustedBuildID: "aaaa"),
                       .buildChanged)
    }

    func testAdHocHintWhenNothingWasTrustedBefore() {
        XCTAssertEqual(CodeSigning.accessibilityHint(isTrusted: false, identity: adHoc, lastTrustedBuildID: nil),
                       .adHocBuild)
        XCTAssertEqual(CodeSigning.accessibilityHint(isTrusted: false, identity: adHoc, lastTrustedBuildID: "bbbb"),
                       .adHocBuild)
    }

    func testNoHintForProperlySignedOrUnknownBuilds() {
        XCTAssertNil(CodeSigning.accessibilityHint(isTrusted: false, identity: signed, lastTrustedBuildID: "aaaa"))
        XCTAssertNil(CodeSigning.accessibilityHint(isTrusted: false, identity: nil, lastTrustedBuildID: "aaaa"))
    }

    func testCurrentIdentityCanBeReadForTheRunningProcess() throws {
        let identity = try XCTUnwrap(CodeSigning.current())
        XCTAssertNotNil(identity.buildID)
    }
}
