import XCTest
@testable import Anchor

final class HotKeyDefaultsTests: XCTestCase {
    func testEnabledSlotIDsCoverDigitRow() {
        XCTAssertEqual(SlotDefaults.enabledSlotIDs, [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
    }

    func testSlotOrderingKeepsZeroAfterNine() {
        XCTAssertEqual(
            SlotDefaults.orderedSlotIDs([0, 3, 1, 9, 2]),
            [1, 2, 3, 9, 0]
        )
    }

    func testDefaultDefinitionsCoverEveryEnabledSlot() throws {
        let definitions = HotKeyDefaults.definitions(for: SlotDefaults.enabledSlotIDs)

        XCTAssertEqual(definitions.count, 10)
        XCTAssertEqual(Set(definitions.map(\.id)).count, 10)
        try HotKeyConfigurationStore.validate(
            HotKeyDefaults.configuration,
            slotIDs: SlotDefaults.enabledSlotIDs
        )
        XCTAssertTrue(definitions.contains(HotKeyDefinition(
            id: 0,
            key: .digit(0),
            modifiers: [.option, .command],
            intent: .focusSlot(0)
        )))
    }

    func testDefaultDefinitionsCreateSwitchHotkeysForEachSlot() {
        let definitions = HotKeyDefaults.definitions(for: [1, 2, 3])

        XCTAssertEqual(definitions.count, 3)
        XCTAssertEqual(Set(definitions.map(\.id)).count, 3)

        XCTAssertTrue(definitions.contains(HotKeyDefinition(
            id: 1,
            key: .digit(1),
            modifiers: [.option, .command],
            intent: .focusSlot(1)
        )))
        XCTAssertTrue(definitions.contains(HotKeyDefinition(
            id: 3,
            key: .digit(3),
            modifiers: [.option, .command],
            intent: .focusSlot(3)
        )))
    }

    func testDefaultConfigurationCreatesSwitchModifiers() {
        let configuration = HotKeyDefaults.configuration

        XCTAssertEqual(configuration.switchModifiers, [.option, .command])
    }

    func testDefinitionsScaleToAdditionalSlots() {
        let definitions = HotKeyDefaults.definitions(for: [4])

        XCTAssertEqual(definitions, [
            HotKeyDefinition(
                id: 4,
                key: .digit(4),
                modifiers: [.option, .command],
                intent: .focusSlot(4)
            )
        ])
    }
}
