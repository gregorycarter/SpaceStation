import XCTest
import Security

final class CodeSigningTests: XCTestCase {
    private let adHocB = CodeSigning.Identity(isAdHoc: true, requirement: #"cdhash H"bbbb""#)
    private let signedA = CodeSigning.Identity(isAdHoc: false, requirement: #"identifier "x" and certificate leaf[subject.CN] = "Dev A""#)

    func testAdHocFlagIsDetected() {
        XCTAssertTrue(CodeSigning.isAdHoc(flags: SecCodeSignatureFlags.adhoc.rawValue))
        XCTAssertTrue(CodeSigning.isAdHoc(flags: SecCodeSignatureFlags.adhoc.rawValue | 0x10000))
        XCTAssertFalse(CodeSigning.isAdHoc(flags: 0x10000)) // e.g. runtime flag only
        XCTAssertFalse(CodeSigning.isAdHoc(flags: 0))
    }

    func testNoHintWhenTrusted() {
        XCTAssertNil(CodeSigning.accessibilityHint(isTrusted: true, identity: adHocB, lastTrustedRequirement: #"cdhash H"aaaa""#))
    }

    func testSignatureChangedForAnyKindOfChange() {
        // ad-hoc build -> different ad-hoc build
        XCTAssertEqual(CodeSigning.accessibilityHint(isTrusted: false, identity: adHocB, lastTrustedRequirement: #"cdhash H"aaaa""#), .signatureChanged)
        // ad-hoc grant -> now signed with a certificate (the real-world case)
        XCTAssertEqual(CodeSigning.accessibilityHint(isTrusted: false, identity: signedA, lastTrustedRequirement: #"cdhash H"aaaa""#), .signatureChanged)
        // certificate A -> certificate B
        XCTAssertEqual(CodeSigning.accessibilityHint(isTrusted: false, identity: signedA, lastTrustedRequirement: #"identifier "x" and certificate leaf[subject.CN] = "Dev B""#), .signatureChanged)
    }

    func testAdHocHintWhenNothingWasTrustedBefore() {
        XCTAssertEqual(CodeSigning.accessibilityHint(isTrusted: false, identity: adHocB, lastTrustedRequirement: nil), .adHocBuild)
        XCTAssertEqual(CodeSigning.accessibilityHint(isTrusted: false, identity: adHocB, lastTrustedRequirement: adHocB.requirement), .adHocBuild)
    }

    func testNoHintWhenSignatureIsUnchangedAndNotAdHoc() {
        // Same stable signature as when it was granted, yet not trusted: the signature doesn't explain it.
        XCTAssertNil(CodeSigning.accessibilityHint(isTrusted: false, identity: signedA, lastTrustedRequirement: signedA.requirement))
        XCTAssertNil(CodeSigning.accessibilityHint(isTrusted: false, identity: signedA, lastTrustedRequirement: nil))
        XCTAssertNil(CodeSigning.accessibilityHint(isTrusted: false, identity: nil, lastTrustedRequirement: "anything"))
    }

    func testCurrentIdentityCanBeReadForTheRunningProcess() throws {
        let identity = try XCTUnwrap(CodeSigning.current())
        XCTAssertNotNil(identity.requirement)
    }
}

final class StaleGrantHealingTests: XCTestCase {
    private let identity = CodeSigning.Identity(isAdHoc: false, requirement: "req-B")

    func testResetsOnceWhenTheSignatureChanged() {
        XCTAssertTrue(CodeSigning.shouldAutoResetStaleGrant(hint: .signatureChanged, identity: identity, lastAutoResetRequirement: nil))
        XCTAssertTrue(CodeSigning.shouldAutoResetStaleGrant(hint: .signatureChanged, identity: identity, lastAutoResetRequirement: "req-A"))
    }

    func testDoesNotRepeatForTheSameSignature() {
        XCTAssertFalse(CodeSigning.shouldAutoResetStaleGrant(hint: .signatureChanged, identity: identity, lastAutoResetRequirement: "req-B"))
    }

    func testNeverResetsWithoutEvidenceOfAStaleGrant() {
        XCTAssertFalse(CodeSigning.shouldAutoResetStaleGrant(hint: nil, identity: identity, lastAutoResetRequirement: nil))
        XCTAssertFalse(CodeSigning.shouldAutoResetStaleGrant(hint: .adHocBuild, identity: identity, lastAutoResetRequirement: nil))
        XCTAssertFalse(CodeSigning.shouldAutoResetStaleGrant(hint: .signatureChanged, identity: nil, lastAutoResetRequirement: nil))
    }
}
