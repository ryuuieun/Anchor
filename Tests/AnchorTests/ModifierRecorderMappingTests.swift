import AppKit
import XCTest
@testable import Anchor

final class ModifierRecorderMappingTests: XCTestCase {
    func testMapsControlShiftOptionCommandOnly() {
        let modifiers = ModifierRecorderMapping.modifiers(from: [
            .control,
            .shift,
            .option,
            .command,
            .shift,
            .capsLock
        ])

        XCTAssertEqual(modifiers, [.control, .shift, .option, .command])
    }

    func testMapsEmptyFlagsToEmptyModifiers() {
        XCTAssertEqual(ModifierRecorderMapping.modifiers(from: []), [])
    }
}
