import Foundation
import os

private let hotKeyLogger = AnchorLog.hotkeys

final class HotKeyManager: ObservableObject {
    @Published private(set) var statusMessage = "Hotkeys not registered"
    @Published private(set) var configuration: HotKeyConfiguration
    @Published private(set) var definitions: [HotKeyDefinition]

    private let slotIDs: [Int]
    private let configurationStore: HotKeyConfigurationStore
    private let registrar: HotKeyRegistrar
    private var intentHandler: ((HotKeyIntent) -> Void)?

    init(
        slotIDs: [Int],
        registrar: HotKeyRegistrar,
        configurationStore: HotKeyConfigurationStore? = nil
    ) {
        self.slotIDs = slotIDs
        self.configurationStore = configurationStore ?? HotKeyConfigurationStore(slotIDs: slotIDs)
        self.registrar = registrar
        configuration = self.configurationStore.configuration
        definitions = self.configurationStore.definitions
        hotKeyLogger.info("HotKeyManager initialized with \(slotIDs.count) slots")
    }

    deinit {
        hotKeyLogger.info("HotKeyManager deinit; unregistering hotkeys")
        registrar.unregisterAll()
    }

    func start(handler: @escaping (HotKeyIntent) -> Void) {
        hotKeyLogger.info("Starting hotkey manager")
        intentHandler = handler
        registerCurrentDefinitions()
    }

    func shortcut(for intent: HotKeyIntent) -> HotKeyShortcut {
        configurationStore.shortcut(for: intent)
    }

    @discardableResult
    func updateModifiers(for action: HotKeyAction, modifiers: HotKeyModifiers) -> Bool {
        hotKeyLogger.info("Updating \(action.displayName, privacy: .public) hotkey modifiers to \(modifiers.displayLabel, privacy: .public)")
        do {
            let nextConfiguration = try configurationStore.configuration(
                updating: action,
                modifiers: modifiers
            )
            try apply(nextConfiguration)
            hotKeyLogger.info("Updated \(action.displayName, privacy: .public) hotkey modifiers")
            return true
        } catch {
            statusMessage = error.localizedDescription
            hotKeyLogger.error("Failed to update \(action.displayName, privacy: .public) hotkey modifiers: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func resetToDefaults() {
        hotKeyLogger.info("Resetting hotkeys to defaults")
        do {
            try apply(HotKeyConfigurationStore.defaultConfiguration)
            hotKeyLogger.info("Reset hotkeys to defaults")
        } catch {
            statusMessage = error.localizedDescription
            hotKeyLogger.error("Failed to reset hotkeys to defaults: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncConfigurationState() {
        configuration = configurationStore.configuration
        definitions = configurationStore.definitions
    }

    private func registerCurrentDefinitions() {
        hotKeyLogger.info("Registering current hotkey definitions count=\(self.definitions.count)")
        do {
            try HotKeyConfigurationStore.validate(configuration, slotIDs: slotIDs)
            try register(definitions)
            statusMessage = registrationStatusMessage(for: definitions.count)
            hotKeyLogger.info("\(self.statusMessage, privacy: .public)")
        } catch {
            statusMessage = error.localizedDescription
            hotKeyLogger.error("Failed to register current hotkey definitions: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ nextConfiguration: HotKeyConfiguration) throws {
        let nextDefinitions = nextConfiguration.definitions(for: slotIDs)
        let previousDefinitions = definitions
        try HotKeyConfigurationStore.validate(nextConfiguration, slotIDs: slotIDs)
        do {
            try register(nextDefinitions)
        } catch {
            hotKeyLogger.error("Hotkey registration failed; attempting rollback: \(error.localizedDescription, privacy: .public)")
            try? register(previousDefinitions)
            throw error
        }
        try configurationStore.replace(with: nextConfiguration)
        syncConfigurationState()
        statusMessage = registrationStatusMessage(for: definitions.count)
        hotKeyLogger.info("\(self.statusMessage, privacy: .public)")
    }

    private func register(_ definitions: [HotKeyDefinition]) throws {
        hotKeyLogger.debug("Registering hotkeys: \(definitions.map(\.label).joined(separator: ", "), privacy: .public)")
        try registrar.register(definitions) { [weak self] intent in
            hotKeyLogger.info("Hotkey callback received: \(intent.logLabel, privacy: .public)")
            self?.statusMessage = intent.statusMessage
            self?.intentHandler?(intent)
        }
    }

    private func registrationStatusMessage(for count: Int) -> String {
        "Registered \(count) global hotkey\(count == 1 ? "" : "s")"
    }
}

private extension HotKeyIntent {
    var logLabel: String {
        switch self {
        case .focusSlot(let slotID):
            return "focusSlot(\(slotID))"
        }
    }

    var statusMessage: String {
        switch self {
        case .focusSlot(let slotID):
            return "Switch hotkey pressed for slot \(slotID)"
        }
    }
}
