import Carbon
import XCTest
@testable import Anchor

final class CarbonHotKeyMappingTests: XCTestCase {
    func testDigitKeyCodesMapToANSIKeys() throws {
        XCTAssertEqual(try CarbonHotKeyMapping.keyCode(for: .digit(1)), UInt32(kVK_ANSI_1))
        XCTAssertEqual(try CarbonHotKeyMapping.keyCode(for: .digit(5)), UInt32(kVK_ANSI_5))
        XCTAssertEqual(try CarbonHotKeyMapping.keyCode(for: .digit(0)), UInt32(kVK_ANSI_0))
    }

    func testUnsupportedDigitThrows() {
        do {
            _ = try CarbonHotKeyMapping.keyCode(for: .digit(10))
            XCTFail("Expected unsupported key error")
        } catch HotKeyRegistrationError.unsupportedKey(.digit(10)) {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testModifiersMapToCarbonFlags() {
        XCTAssertEqual(CarbonHotKeyMapping.modifiers(for: []), 0)
        XCTAssertEqual(CarbonHotKeyMapping.modifiers(for: [.option, .command]), UInt32(optionKey) | UInt32(cmdKey))
        XCTAssertEqual(
            CarbonHotKeyMapping.modifiers(for: [.control, .shift, .option, .command]),
            UInt32(controlKey) | UInt32(shiftKey) | UInt32(optionKey) | UInt32(cmdKey)
        )
    }
}
