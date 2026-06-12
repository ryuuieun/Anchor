import ApplicationServices
import XCTest
@testable import Anchor

final class WindowFocusVerifierTests: XCTestCase {
    func testFocusedWindowMatchVerifiesFocus() {
        let targetHandle = TestFocusWindowElementHandle(id: 1)
        let window = makeFocusWindow(handle: targetHandle)
        let reader = MockWindowFocusVerificationReader(handlesByAttribute: [
            kAXFocusedWindowAttribute as String: targetHandle
        ])
        let verifier = WindowFocusVerifier(reader: reader)

        XCTAssertTrue(verifier.verifiesFocus(for: window))
    }

    func testMainWindowMatchVerifiesFocusWhenFocusedWindowIsUnavailable() {
        let targetHandle = TestFocusWindowElementHandle(id: 1)
        let window = makeFocusWindow(handle: targetHandle)
        let reader = MockWindowFocusVerificationReader(handlesByAttribute: [
            kAXMainWindowAttribute as String: targetHandle
        ])
        let verifier = WindowFocusVerifier(reader: reader)

        XCTAssertTrue(verifier.verifiesFocus(for: window))
    }

    func testMainWindowMatchVerifiesFocusWhenFocusedWindowDoesNotMatch() {
        let targetHandle = TestFocusWindowElementHandle(id: 1)
        let window = makeFocusWindow(handle: targetHandle)
        let reader = MockWindowFocusVerificationReader(handlesByAttribute: [
            kAXFocusedWindowAttribute as String: TestFocusWindowElementHandle(id: 2),
            kAXMainWindowAttribute as String: targetHandle
        ])
        let verifier = WindowFocusVerifier(reader: reader)

        XCTAssertTrue(verifier.verifiesFocus(for: window))
    }

    func testNonMatchingFocusedAndMainWindowsDoNotVerifyFocus() {
        let window = makeFocusWindow(handle: TestFocusWindowElementHandle(id: 1))
        let reader = MockWindowFocusVerificationReader(handlesByAttribute: [
            kAXFocusedWindowAttribute as String: TestFocusWindowElementHandle(id: 2),
            kAXMainWindowAttribute as String: TestFocusWindowElementHandle(id: 3)
        ])
        let verifier = WindowFocusVerifier(reader: reader)

        XCTAssertFalse(verifier.verifiesFocus(for: window))
    }
}

private final class MockWindowFocusVerificationReader: WindowFocusVerificationReading {
    let handlesByAttribute: [String: WindowElementHandle]

    init(handlesByAttribute: [String: WindowElementHandle]) {
        self.handlesByAttribute = handlesByAttribute
    }

    func windowHandle(pid: pid_t, attribute: String) -> WindowElementHandle? {
        handlesByAttribute[attribute]
    }
}

private final class TestFocusWindowElementHandle: WindowElementHandle {
    let id: Int

    init(id: Int) {
        self.id = id
    }

    func isSameWindow(as other: WindowElementHandle) -> Bool {
        guard let other = other as? TestFocusWindowElementHandle else {
            return false
        }
        return id == other.id
    }
}

private func makeFocusWindow(handle: WindowElementHandle) -> WindowReference {
    let fingerprint = WindowFingerprint(
        pid: 10_000,
        bundleIdentifier: "dev.test.App",
        title: "Window",
        role: "AXWindow",
        subrole: "AXStandardWindow",
        identifier: nil,
        position: nil,
        size: nil,
        cgWindowID: nil,
        cgBounds: nil,
        cgLayer: nil
    )

    return WindowReference(
        handle: handle,
        pid: 10_000,
        appName: "Test App",
        bundleIdentifier: "dev.test.App",
        bundleURL: nil,
        title: "Window",
        role: "AXWindow",
        subrole: "AXStandardWindow",
        identifier: nil,
        fingerprint: fingerprint
    )
}
