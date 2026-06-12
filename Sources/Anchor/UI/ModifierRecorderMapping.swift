import AppKit
import Foundation

enum ModifierRecorderMapping {
    static func modifiers(from flags: NSEvent.ModifierFlags) -> HotKeyModifiers {
        var modifiers: HotKeyModifiers = []
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        return modifiers
    }
}
