import Foundation

enum HotKeyIntent: Equatable, Hashable, Codable {
    case focusSlot(Int)

    var id: UInt32 {
        switch self {
        case .focusSlot(let slotID):
            return UInt32(slotID)
        }
    }

    var slotID: Int {
        switch self {
        case .focusSlot(let slotID):
            return slotID
        }
    }
}

enum HotKeyAction: String, CaseIterable, Identifiable, Codable {
    case switchSlot

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .switchSlot:
            return "Switch"
        }
    }
}

struct HotKeyModifiers: OptionSet, Equatable, Hashable, Codable {
    let rawValue: UInt

    static let control = HotKeyModifiers(rawValue: 1 << 0)
    static let option = HotKeyModifiers(rawValue: 1 << 1)
    static let command = HotKeyModifiers(rawValue: 1 << 2)
    static let shift = HotKeyModifiers(rawValue: 1 << 3)

    init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UInt.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum PhysicalKey: Equatable, Hashable, Codable, Identifiable {
    case digit(Int)

    static let supportedDigits: [PhysicalKey] = [
        .digit(1), .digit(2), .digit(3), .digit(4), .digit(5),
        .digit(6), .digit(7), .digit(8), .digit(9), .digit(0)
    ]

    var id: Int {
        digitValue
    }

    var digitValue: Int {
        switch self {
        case .digit(let value):
            return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = .digit(try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(digitValue)
    }
}

struct HotKeyDefinition: Identifiable, Equatable {
    let id: UInt32
    let key: PhysicalKey
    let modifiers: HotKeyModifiers
    let intent: HotKeyIntent

    init(id: UInt32, key: PhysicalKey, modifiers: HotKeyModifiers, intent: HotKeyIntent) {
        self.id = id
        self.key = key
        self.modifiers = modifiers
        self.intent = intent
    }

    init(intent: HotKeyIntent, shortcut: HotKeyShortcut) {
        self.init(
            id: intent.id,
            key: shortcut.key,
            modifiers: shortcut.modifiers,
            intent: intent
        )
    }

    init(intent: HotKeyIntent, configuration: HotKeyConfiguration) {
        self.init(
            intent: intent,
            shortcut: configuration.shortcut(for: intent)
        )
    }

    var shortcut: HotKeyShortcut {
        HotKeyShortcut(key: key, modifiers: modifiers)
    }

    var label: String {
        switch intent {
        case .focusSlot(let slotID):
            return "Switch slot \(slotID): \(modifiers.displayLabel)+\(key.displayLabel)"
        }
    }
}

struct HotKeyShortcut: Codable, Equatable, Hashable {
    var key: PhysicalKey
    var modifiers: HotKeyModifiers

    var displayLabel: String {
        "\(modifiers.displayLabel)+\(key.displayLabel)"
    }
}

struct HotKeyConfiguration: Codable, Equatable {
    var switchModifiers: HotKeyModifiers

    func modifiers(for action: HotKeyAction) -> HotKeyModifiers {
        switch action {
        case .switchSlot:
            return switchModifiers
        }
    }

    mutating func setModifiers(_ modifiers: HotKeyModifiers, for action: HotKeyAction) {
        switch action {
        case .switchSlot:
            switchModifiers = modifiers
        }
    }

    func shortcut(for intent: HotKeyIntent) -> HotKeyShortcut {
        switch intent {
        case .focusSlot(let slotID):
            return HotKeyShortcut(key: .digit(slotID), modifiers: switchModifiers)
        }
    }

    func definitions(for slotIDs: [Int]) -> [HotKeyDefinition] {
        slotIDs.map { slotID in
            HotKeyDefinition(intent: .focusSlot(slotID), configuration: self)
        }
    }
}

enum HotKeyDefaults {
    static var configuration: HotKeyConfiguration {
        HotKeyConfiguration(
            switchModifiers: [.option, .command]
        )
    }

    static func definitions(for slotIDs: [Int]) -> [HotKeyDefinition] {
        configuration.definitions(for: slotIDs)
    }
}

extension HotKeyModifiers {
    var displayLabel: String {
        var parts: [String] = []
        if contains(.control) {
            parts.append("Control")
        }
        if contains(.shift) {
            parts.append("Shift")
        }
        if contains(.option) {
            parts.append("Option")
        }
        if contains(.command) {
            parts.append("Command")
        }
        return parts.isEmpty ? "None" : parts.joined(separator: "+")
    }
}

extension PhysicalKey {
    var displayLabel: String {
        switch self {
        case .digit(let value):
            return "\(value)"
        }
    }
}
