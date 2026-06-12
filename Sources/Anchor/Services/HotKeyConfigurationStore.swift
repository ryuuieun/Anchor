import Foundation
import os

private let hotKeyConfigurationLogger = AnchorLog.hotkeys

enum HotKeyConfigurationValidationError: LocalizedError, Equatable {
    case missingModifier(HotKeyAction)
    case duplicateShortcut(HotKeyShortcut)

    var errorDescription: String? {
        switch self {
        case .missingModifier(let action):
            return "\(action.displayName) requires at least one modifier"
        case .duplicateShortcut(let shortcut):
            return "Duplicate hotkey: \(shortcut.displayLabel)"
        }
    }
}

final class HotKeyConfigurationStore {
    private let slotIDs: [Int]
    private let userDefaults: UserDefaults
    private let storageKey: String

    private(set) var configuration: HotKeyConfiguration

    init(
        slotIDs: [Int],
        userDefaults: UserDefaults = .standard,
        storageKey: String = "HotKeyConfiguration.v2"
    ) {
        self.slotIDs = slotIDs
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        configuration = Self.loadConfiguration(
            slotIDs: slotIDs,
            userDefaults: userDefaults,
            storageKey: storageKey
        )
        hotKeyConfigurationLogger.info("Loaded hotkey configuration for \(slotIDs.count) slots")
    }

    var definitions: [HotKeyDefinition] {
        configuration.definitions(for: slotIDs)
    }

    func shortcut(for intent: HotKeyIntent) -> HotKeyShortcut {
        configuration.shortcut(for: intent)
    }

    func modifiers(for action: HotKeyAction) -> HotKeyModifiers {
        configuration.modifiers(for: action)
    }

    func updateModifiers(_ modifiers: HotKeyModifiers, for action: HotKeyAction) throws {
        try replace(with: configuration(updating: action, modifiers: modifiers))
    }

    func resetDefaults() {
        configuration = Self.defaultConfiguration
        save()
        hotKeyConfigurationLogger.info("Reset hotkey configuration to defaults")
    }

    func configuration(updating action: HotKeyAction, modifiers: HotKeyModifiers) throws -> HotKeyConfiguration {
        var nextConfiguration = configuration
        nextConfiguration.setModifiers(modifiers, for: action)
        try Self.validate(nextConfiguration, slotIDs: slotIDs)
        return nextConfiguration
    }

    func replace(with nextConfiguration: HotKeyConfiguration) throws {
        try Self.validate(nextConfiguration, slotIDs: slotIDs)
        configuration = nextConfiguration
        save()
        hotKeyConfigurationLogger.info("Replaced hotkey configuration")
    }

    static var defaultConfiguration: HotKeyConfiguration {
        HotKeyDefaults.configuration
    }

    static func validate(_ configuration: HotKeyConfiguration, slotIDs: [Int]) throws {
        var shortcutsByIntent: [(HotKeyIntent, HotKeyShortcut)] = []
        for slotID in slotIDs {
            shortcutsByIntent.append((.focusSlot(slotID), configuration.shortcut(for: .focusSlot(slotID))))
        }

        if configuration.switchModifiers.isEmpty {
            throw HotKeyConfigurationValidationError.missingModifier(.switchSlot)
        }

        var seenShortcuts = Set<HotKeyShortcut>()
        for (_, shortcut) in shortcutsByIntent {
            guard seenShortcuts.insert(shortcut).inserted else {
                throw HotKeyConfigurationValidationError.duplicateShortcut(shortcut)
            }
        }
    }

    private static func loadConfiguration(
        slotIDs: [Int],
        userDefaults: UserDefaults,
        storageKey: String
    ) -> HotKeyConfiguration {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data),
              (try? validate(decoded, slotIDs: slotIDs)) != nil else {
            hotKeyConfigurationLogger.info("Using default hotkey configuration")
            return defaultConfiguration
        }
        hotKeyConfigurationLogger.info("Loaded persisted hotkey configuration")
        return decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configuration) else {
            hotKeyConfigurationLogger.error("Failed to encode hotkey configuration")
            return
        }
        userDefaults.set(data, forKey: storageKey)
        hotKeyConfigurationLogger.debug("Saved hotkey configuration")
    }
}
