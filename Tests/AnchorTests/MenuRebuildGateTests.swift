import XCTest
@testable import Anchor

final class MenuRebuildGateTests: XCTestCase {
    func testRequestRebuildRunsImmediatelyWhenMenuIsClosed() {
        var gate = MenuRebuildGate()

        XCTAssertTrue(gate.requestRebuild())
    }

    func testRequestRebuildDefersWhileMenuIsOpenUntilClose() {
        var gate = MenuRebuildGate()

        gate.menuWillOpen()

        XCTAssertFalse(gate.requestRebuild())
        XCTAssertTrue(gate.menuDidClose())
        XCTAssertFalse(gate.menuDidClose())
    }

    func testMultipleRequestsWhileMenuIsOpenCoalesceToOneCloseRebuild() {
        var gate = MenuRebuildGate()

        gate.menuWillOpen()

        XCTAssertFalse(gate.requestRebuild())
        XCTAssertFalse(gate.requestRebuild())
        XCTAssertTrue(gate.menuDidClose())
        XCTAssertFalse(gate.menuDidClose())
    }
}
