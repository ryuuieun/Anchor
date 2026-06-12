import Carbon
import Foundation

enum CarbonHotKeyMapping {
    static func keyCode(for key: PhysicalKey) throws -> UInt32 {
        switch key {
        case .digit(1):
            return UInt32(kVK_ANSI_1)
        case .digit(2):
            return UInt32(kVK_ANSI_2)
        case .digit(3):
            return UInt32(kVK_ANSI_3)
        case .digit(4):
            return UInt32(kVK_ANSI_4)
        case .digit(5):
            return UInt32(kVK_ANSI_5)
        case .digit(6):
            return UInt32(kVK_ANSI_6)
        case .digit(7):
            return UInt32(kVK_ANSI_7)
        case .digit(8):
            return UInt32(kVK_ANSI_8)
        case .digit(9):
            return UInt32(kVK_ANSI_9)
        case .digit(0):
            return UInt32(kVK_ANSI_0)
        case .digit:
            throw HotKeyRegistrationError.unsupportedKey(key)
        }
    }

    static func modifiers(for modifiers: HotKeyModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.control) {
            result |= UInt32(controlKey)
        }
        if modifiers.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        if modifiers.contains(.option) {
            result |= UInt32(optionKey)
        }
        if modifiers.contains(.command) {
            result |= UInt32(cmdKey)
        }
        return result
    }
}
