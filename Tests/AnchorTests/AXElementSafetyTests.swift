import ApplicationServices
import XCTest
@testable import Anchor

final class AXElementSafetyTests: XCTestCase {
    func testElementRejectsNonAXValuesInsteadOfForceCasting() {
        let value: CFTypeRef = "not an AX element" as CFString

        XCTAssertNil(AXElementSafety.element(from: value))
    }

    func testElementAcceptsAXValues() {
        let element = AXElementSafety.systemWideElement()

        XCTAssertNotNil(AXElementSafety.element(from: element))
    }

    func testAXErrorSeparatesPermissionFailureFromTemporaryUnavailable() {
        XCTAssertTrue(AXError.apiDisabled.isAccessibilityUnavailable)
        XCTAssertFalse(AXError.apiDisabled.isTemporaryUnavailable)
        XCTAssertFalse(AXError.cannotComplete.isAccessibilityUnavailable)
        XCTAssertTrue(AXError.cannotComplete.isTemporaryUnavailable)
    }
}
