import XCTest
@testable import Anchor

final class HotKeyConfigurationStoreTests: XCTestCase {
    func testEmptyStoreUsesDefaultConfigurations() {
        let defaults = makeUserDefaults()
        let store = HotKeyConfigurationStore(slotIDs: [1, 2], userDefaults: defaults)

        XCTAssertEqual(store.configuration, HotKeyDefaults.configuration)
        XCTAssertEqual(store.definitions, HotKeyDefaults.definitions(for: [1, 2]))
    }

    func testUpdateModifiersPersistsConfiguration() throws {
        let defaults = makeUserDefaults()
        let store = HotKeyConfigurationStore(slotIDs: [1], userDefaults: defaults)
        let customModifiers: HotKeyModifiers = [.control, .command]

        try store.updateModifiers(customModifiers, for: .switchSlot)

        let reloadedStore = HotKeyConfigurationStore(slotIDs: [1], userDefaults: defaults)
        XCTAssertEqual(reloadedStore.configuration.switchModifiers, customModifiers)
        XCTAssertEqual(reloadedStore.shortcut(for: .focusSlot(1)), HotKeyShortcut(
            key: .digit(1),
            modifiers: customModifiers
        ))
    }

    func testResetDefaultsPersistsDefaultConfiguration() throws {
        let defaults = makeUserDefaults()
        let store = HotKeyConfigurationStore(slotIDs: [1], userDefaults: defaults)
        try store.updateModifiers([.control, .command], for: .switchSlot)

        store.resetDefaults()

        let reloadedStore = HotKeyConfigurationStore(slotIDs: [1], userDefaults: defaults)
        XCTAssertEqual(reloadedStore.configuration, HotKeyDefaults.configuration)
    }

    func testRejectsShortcutWithoutModifiers() {
        let store = HotKeyConfigurationStore(slotIDs: [1], userDefaults: makeUserDefaults())

        XCTAssertThrowsError(try store.updateModifiers(
            [],
            for: .switchSlot
        )) { error in
            XCTAssertEqual(error as? HotKeyConfigurationValidationError, .missingModifier(.switchSlot))
        }
    }

    func testRejectsDuplicateShortcuts() {
        XCTAssertThrowsError(try HotKeyConfigurationStore.validate(
            HotKeyDefaults.configuration,
            slotIDs: [1, 1]
        )) { error in
            XCTAssertEqual(
                error as? HotKeyConfigurationValidationError,
                .duplicateShortcut(HotKeyShortcut(key: .digit(1), modifiers: [.option, .command]))
            )
        }
    }

    func testAcceptsSwitchModifierUpdate() throws {
        let store = HotKeyConfigurationStore(slotIDs: [1], userDefaults: makeUserDefaults())

        try store.updateModifiers([.shift, .command], for: .switchSlot)
        try store.updateModifiers([.option, .command], for: .switchSlot)

        XCTAssertEqual(store.configuration.switchModifiers, [.option, .command])
    }

    func testInvalidPersistedConfigurationFallsBackToDefaults() throws {
        let defaults = makeUserDefaults()
        let invalidConfiguration = HotKeyConfiguration(
            switchModifiers: []
        )
        let data = try JSONEncoder().encode(invalidConfiguration)
        defaults.set(data, forKey: "HotKeyConfiguration.v2")

        let store = HotKeyConfigurationStore(slotIDs: [1], userDefaults: defaults)

        XCTAssertEqual(store.configuration, HotKeyDefaults.configuration)
    }

    func testLegacyPersistedBindModifiersAreIgnored() {
        let defaults = makeUserDefaults()
        let legacyJSON = #"{"switchModifiers":6,"bindModifiers":7}"#
        defaults.set(Data(legacyJSON.utf8), forKey: "HotKeyConfiguration.v2")

        let store = HotKeyConfigurationStore(slotIDs: [1], userDefaults: defaults)

        XCTAssertEqual(store.configuration, HotKeyConfiguration(switchModifiers: [.option, .command]))
        XCTAssertEqual(store.definitions, [
            HotKeyDefinition(
                intent: .focusSlot(1),
                shortcut: HotKeyShortcut(key: .digit(1), modifiers: [.option, .command])
            )
        ])
    }

    func testDefinitionsAlwaysUseSlotIDAsDigitKey() throws {
        let store = HotKeyConfigurationStore(slotIDs: [0, 1, 9], userDefaults: makeUserDefaults())
        try store.updateModifiers([.control], for: .switchSlot)

        XCTAssertTrue(store.definitions.contains(HotKeyDefinition(
            intent: .focusSlot(0),
            shortcut: HotKeyShortcut(key: .digit(0), modifiers: [.control])
        )))
        XCTAssertTrue(store.definitions.contains(HotKeyDefinition(
            intent: .focusSlot(9),
            shortcut: HotKeyShortcut(key: .digit(9), modifiers: [.control])
        )))
    }
}

func makeUserDefaults(
    file: StaticString = #filePath,
    line: UInt = #line
) -> UserDefaults {
    let suiteName = "AnchorTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        XCTFail("Could not create UserDefaults suite", file: file, line: line)
        return .standard
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
