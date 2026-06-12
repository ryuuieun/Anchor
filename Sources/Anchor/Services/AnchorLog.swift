import os

enum AnchorLog {
    static let subsystem = "dev.ryuuieun.Anchor"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let menu = Logger(subsystem: subsystem, category: "menu")
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let slots = Logger(subsystem: subsystem, category: "slots")
    static let ax = Logger(subsystem: subsystem, category: "ax")
    static let focus = Logger(subsystem: subsystem, category: "focus")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
