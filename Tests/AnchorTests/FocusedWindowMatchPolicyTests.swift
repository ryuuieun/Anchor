import XCTest
@testable import Anchor

final class FocusedWindowMatchPolicyTests: XCTestCase {
    func testAllowsWorkspaceFrontmostWhenAXFocusedApplicationIsUnavailable() {
        XCTAssertTrue(FocusedWindowMatchPolicy.targetApplicationCanOwnFocusedWindow(
            targetPID: 100,
            ownPID: 200,
            axFocusedApplicationPID: nil,
            workspaceFrontmostPID: 100
        ))
    }

    func testAllowsAXFocusedApplicationWhenWorkspaceFrontmostIsUnavailable() {
        XCTAssertTrue(FocusedWindowMatchPolicy.targetApplicationCanOwnFocusedWindow(
            targetPID: 100,
            ownPID: 200,
            axFocusedApplicationPID: 100,
            workspaceFrontmostPID: nil
        ))
    }

    func testRejectsBackgroundTarget() {
        XCTAssertFalse(FocusedWindowMatchPolicy.targetApplicationCanOwnFocusedWindow(
            targetPID: 100,
            ownPID: 200,
            axFocusedApplicationPID: nil,
            workspaceFrontmostPID: 300
        ))
    }

    func testRejectsOwnApplication() {
        XCTAssertFalse(FocusedWindowMatchPolicy.targetApplicationCanOwnFocusedWindow(
            targetPID: 200,
            ownPID: 200,
            axFocusedApplicationPID: 200,
            workspaceFrontmostPID: 200
        ))
    }
}
