import XCTest
@testable import Anchor

final class HotKeyManagerTests: XCTestCase {
    func testStartRegistersDefinitionsAndUpdatesStatus() {
        let registrar = MockHotKeyRegistrar()
        let manager = HotKeyManager(
            slotIDs: [1, 2],
            registrar: registrar,
            configurationStore: HotKeyConfigurationStore(slotIDs: [1, 2], userDefaults: makeUserDefaults())
        )

        manager.start { _ in }

        XCTAssertEqual(registrar.registeredDefinitions, HotKeyDefaults.definitions(for: [1, 2]))
        XCTAssertEqual(manager.statusMessage, "Registered 2 global hotkeys")
    }

    func testRegisteredHandlerUpdatesStatusAndForwardsIntent() {
        let registrar = MockHotKeyRegistrar()
        let manager = HotKeyManager(
            slotIDs: [1],
            registrar: registrar,
            configurationStore: HotKeyConfigurationStore(slotIDs: [1], userDefaults: makeUserDefaults())
        )
        var receivedIntent: HotKeyIntent?

        manager.start { intent in
            receivedIntent = intent
        }
        registrar.trigger(.focusSlot(1))

        XCTAssertEqual(receivedIntent, .focusSlot(1))
        XCTAssertEqual(manager.statusMessage, "Switch hotkey pressed for slot 1")
    }

    func testRegistrationFailureUpdatesStatusMessage() {
        let registrar = MockHotKeyRegistrar()
        registrar.errorToThrow = MockHotKeyError.registrationFailed
        let manager = HotKeyManager(
            slotIDs: [1],
            registrar: registrar,
            configurationStore: HotKeyConfigurationStore(slotIDs: [1], userDefaults: makeUserDefaults())
        )

        manager.start { _ in }

        XCTAssertEqual(manager.statusMessage, "Mock registration failed")
    }

    func testDeinitUnregistersAllHotkeys() {
        let registrar = MockHotKeyRegistrar()
        var manager: HotKeyManager? = HotKeyManager(
            slotIDs: [1],
            registrar: registrar,
            configurationStore: HotKeyConfigurationStore(slotIDs: [1], userDefaults: makeUserDefaults())
        )

        XCTAssertNotNil(manager)
        XCTAssertFalse(registrar.didUnregisterAll)
        manager = nil

        XCTAssertTrue(registrar.didUnregisterAll)
    }

    func testUpdateModifiersPersistsAndReregistersDefinitions() {
        let registrar = MockHotKeyRegistrar()
        let store = HotKeyConfigurationStore(slotIDs: [1], userDefaults: makeUserDefaults())
        let manager = HotKeyManager(slotIDs: [1], registrar: registrar, configurationStore: store)
        manager.start { _ in }
        let customModifiers: HotKeyModifiers = [.control, .command]

        let didUpdate = manager.updateModifiers(for: .switchSlot, modifiers: customModifiers)

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(manager.shortcut(for: .focusSlot(1)), HotKeyShortcut(
            key: .digit(1),
            modifiers: customModifiers
        ))
        XCTAssertTrue(registrar.registeredDefinitions.contains(HotKeyDefinition(
            intent: .focusSlot(1),
            shortcut: HotKeyShortcut(key: .digit(1), modifiers: customModifiers)
        )))
        XCTAssertEqual(manager.statusMessage, "Registered 1 global hotkey")
    }

    func testRegistrationFailureDuringUpdateKeepsPreviousConfiguration() {
        let registrar = MockHotKeyRegistrar()
        let defaults = makeUserDefaults()
        let store = HotKeyConfigurationStore(slotIDs: [1], userDefaults: defaults)
        let manager = HotKeyManager(slotIDs: [1], registrar: registrar, configurationStore: store)
        manager.start { _ in }
        let originalConfiguration = manager.configuration
        let originalDefinitions = registrar.registeredDefinitions
        registrar.clearsDefinitionsBeforeThrowing = true
        registrar.registerErrors = [MockHotKeyError.registrationFailed]

        let didUpdate = manager.updateModifiers(for: .switchSlot, modifiers: [.shift, .command])

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(manager.configuration, originalConfiguration)
        XCTAssertEqual(store.configuration, originalConfiguration)
        XCTAssertEqual(registrar.registeredDefinitions, originalDefinitions)
        XCTAssertEqual(manager.statusMessage, "Mock registration failed")

        let reloadedStore = HotKeyConfigurationStore(slotIDs: [1], userDefaults: defaults)
        XCTAssertEqual(reloadedStore.configuration, originalConfiguration)
    }

    func testInvalidShortcutDoesNotReregisterDefinitions() {
        let registrar = MockHotKeyRegistrar()
        let store = HotKeyConfigurationStore(slotIDs: [1], userDefaults: makeUserDefaults())
        let manager = HotKeyManager(slotIDs: [1], registrar: registrar, configurationStore: store)
        manager.start { _ in }
        registrar.registeredDefinitions.removeAll()

        let didUpdate = manager.updateModifiers(for: .switchSlot, modifiers: [])

        XCTAssertFalse(didUpdate)
        XCTAssertTrue(registrar.registeredDefinitions.isEmpty)
        XCTAssertEqual(manager.statusMessage, "Switch requires at least one modifier")
    }

    func testResetToDefaultsRestoresDefaultDefinitions() {
        let registrar = MockHotKeyRegistrar()
        let store = HotKeyConfigurationStore(slotIDs: [1], userDefaults: makeUserDefaults())
        let manager = HotKeyManager(slotIDs: [1], registrar: registrar, configurationStore: store)
        manager.start { _ in }
        _ = manager.updateModifiers(for: .switchSlot, modifiers: [.control, .command])

        manager.resetToDefaults()

        XCTAssertEqual(manager.configuration, HotKeyDefaults.configuration)
        XCTAssertEqual(registrar.registeredDefinitions, HotKeyDefaults.definitions(for: [1]))
    }

    func testRegistrationFailureDuringResetKeepsPreviousConfiguration() {
        let registrar = MockHotKeyRegistrar()
        let defaults = makeUserDefaults()
        let store = HotKeyConfigurationStore(slotIDs: [1], userDefaults: defaults)
        let manager = HotKeyManager(slotIDs: [1], registrar: registrar, configurationStore: store)
        manager.start { _ in }
        XCTAssertTrue(manager.updateModifiers(for: .switchSlot, modifiers: [.shift, .command]))
        let customConfiguration = manager.configuration
        let customDefinitions = registrar.registeredDefinitions
        registrar.clearsDefinitionsBeforeThrowing = true
        registrar.registerErrors = [MockHotKeyError.registrationFailed]

        manager.resetToDefaults()

        XCTAssertEqual(manager.configuration, customConfiguration)
        XCTAssertEqual(store.configuration, customConfiguration)
        XCTAssertEqual(registrar.registeredDefinitions, customDefinitions)
        XCTAssertEqual(manager.statusMessage, "Mock registration failed")

        let reloadedStore = HotKeyConfigurationStore(slotIDs: [1], userDefaults: defaults)
        XCTAssertEqual(reloadedStore.configuration, customConfiguration)
    }
}

private final class MockHotKeyRegistrar: HotKeyRegistrar {
    var registeredDefinitions: [HotKeyDefinition] = []
    var registeredHandler: ((HotKeyIntent) -> Void)?
    var errorToThrow: Error?
    var registerErrors: [Error] = []
    var clearsDefinitionsBeforeThrowing = false
    var didUnregisterAll = false

    func register(_ definitions: [HotKeyDefinition], handler: @escaping (HotKeyIntent) -> Void) throws {
        if !registerErrors.isEmpty {
            if clearsDefinitionsBeforeThrowing {
                registeredDefinitions = []
                registeredHandler = nil
            }
            throw registerErrors.removeFirst()
        }
        if let errorToThrow {
            if clearsDefinitionsBeforeThrowing {
                registeredDefinitions = []
                registeredHandler = nil
            }
            throw errorToThrow
        }
        registeredDefinitions = definitions
        registeredHandler = handler
    }

    func unregisterAll() {
        didUnregisterAll = true
    }

    func trigger(_ intent: HotKeyIntent) {
        registeredHandler?(intent)
    }
}

private enum MockHotKeyError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        "Mock registration failed"
    }
}
