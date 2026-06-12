import CoreGraphics
import XCTest
@testable import Anchor

final class WindowFingerprintMatcherTests: XCTestCase {
    func testUniqueIdentifierMatchWins() {
        let original = fingerprint(title: "Original", identifier: "window-a")
        let candidates = [
            fingerprint(title: "Other", identifier: "window-b"),
            fingerprint(title: "Retitled", identifier: "window-a")
        ]

        XCTAssertEqual(
            WindowFingerprintMatcher.match(original: original, candidates: candidates),
            .match(1)
        )
    }

    func testDuplicateIdentifierIsAmbiguous() {
        let original = fingerprint(identifier: "window-a")
        let candidates = [
            fingerprint(identifier: "window-a"),
            fingerprint(identifier: "window-a")
        ]

        XCTAssertEqual(
            WindowFingerprintMatcher.match(original: original, candidates: candidates),
            .ambiguous("window identity ambiguous")
        )
    }

    func testCGWindowIDFallbackMatchesUniquely() {
        let original = fingerprint(cgWindowID: 42)
        let candidates = [
            fingerprint(cgWindowID: 41),
            fingerprint(cgWindowID: 42)
        ]

        XCTAssertEqual(
            WindowFingerprintMatcher.match(original: original, candidates: candidates),
            .match(1)
        )
    }

    func testDuplicateCGWindowIDIsAmbiguous() {
        let original = fingerprint(cgWindowID: 42)
        let candidates = [
            fingerprint(cgWindowID: 42),
            fingerprint(cgWindowID: 42)
        ]

        XCTAssertEqual(
            WindowFingerprintMatcher.match(original: original, candidates: candidates),
            .ambiguous("window identity ambiguous")
        )
    }

    func testTitleAndGeometryFallbackMatchesWithinTolerance() {
        let original = fingerprint(
            title: "Untitled",
            position: CGPoint(x: 100, y: 120),
            size: CGSize(width: 900, height: 600)
        )
        let candidates = [
            fingerprint(
                title: "Untitled",
                position: CGPoint(x: 105, y: 126),
                size: CGSize(width: 904, height: 596)
            )
        ]

        XCTAssertEqual(
            WindowFingerprintMatcher.match(original: original, candidates: candidates),
            .match(0)
        )
    }

    func testTitleOnlyMatchIsAmbiguous() {
        let original = fingerprint(title: "Untitled")
        let candidates = [
            fingerprint(title: "Untitled")
        ]

        XCTAssertEqual(
            WindowFingerprintMatcher.match(original: original, candidates: candidates),
            .ambiguous("window identity ambiguous")
        )
    }

    func testDifferentTitleWithoutStrongIdentityIsMissing() {
        let original = fingerprint(
            title: "Original",
            position: CGPoint(x: 100, y: 100),
            size: CGSize(width: 800, height: 600)
        )
        let candidates = [
            fingerprint(
                title: "Different",
                position: CGPoint(x: 100, y: 100),
                size: CGSize(width: 800, height: 600)
            )
        ]

        XCTAssertEqual(
            WindowFingerprintMatcher.match(original: original, candidates: candidates),
            .missing
        )
    }

    func testIncompatibleCandidatesAreIgnored() {
        let original = fingerprint(pid: 100, title: "Window")
        let candidates = [
            fingerprint(pid: 200, title: "Window", identifier: "same-looking-window")
        ]

        XCTAssertEqual(
            WindowFingerprintMatcher.match(original: original, candidates: candidates),
            .missing
        )
    }

    func testNilOriginalSubroleAllowsCompatibleIdentifierMatch() {
        let original = fingerprint(subrole: nil, identifier: "window-a")
        let candidates = [
            fingerprint(subrole: "AXDialog", identifier: "window-a")
        ]

        XCTAssertEqual(
            WindowFingerprintMatcher.match(original: original, candidates: candidates),
            .match(0)
        )
    }

    func testOriginalSubroleMustMatchWhenPresent() {
        let original = fingerprint(subrole: "AXStandardWindow", identifier: "window-a")
        let candidates = [
            fingerprint(subrole: "AXDialog", identifier: "window-a")
        ]

        XCTAssertEqual(
            WindowFingerprintMatcher.match(original: original, candidates: candidates),
            .missing
        )
    }

    private func fingerprint(
        pid: pid_t = 100,
        bundleIdentifier: String? = "dev.test.App",
        title: String = "Window",
        role: String = "AXWindow",
        subrole: String? = "AXStandardWindow",
        identifier: String? = nil,
        position: CGPoint? = nil,
        size: CGSize? = nil,
        cgWindowID: CGWindowID? = nil,
        cgBounds: CGRect? = nil,
        cgLayer: Int? = 0
    ) -> WindowFingerprint {
        WindowFingerprint(
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            title: title,
            role: role,
            subrole: subrole,
            identifier: identifier,
            position: position,
            size: size,
            cgWindowID: cgWindowID,
            cgBounds: cgBounds,
            cgLayer: cgLayer
        )
    }
}
