import AppKit
import XCTest
@testable import Anchor

final class SettingsWindowControllerTests: XCTestCase {
    @MainActor
    func testSettingsWindowUsesCompactContentHeight() {
        let controller = SettingsWindowController(
            permissionService: AccessibilityPermissionService(),
            hotKeyManager: HotKeyManager(
                slotIDs: [1],
                registrar: SettingsWindowMockHotKeyRegistrar()
            ),
            optionDoubleTapSettingsStore: OptionDoubleTapSettingsStore(userDefaults: makeUserDefaults())
        )

        guard let contentBounds = controller.window?.contentView?.bounds else {
            XCTFail("Settings window is missing a content view")
            return
        }

        XCTAssertEqual(
            Double(contentBounds.width),
            Double(SettingsWindowController.defaultContentSize.width),
            accuracy: 0.5
        )
        XCTAssertEqual(
            Double(contentBounds.height),
            Double(SettingsWindowController.defaultContentSize.height),
            accuracy: 0.5
        )
    }
}

private final class SettingsWindowMockHotKeyRegistrar: HotKeyRegistrar {
    func register(_ definitions: [HotKeyDefinition], handler: @escaping (HotKeyIntent) -> Void) throws {}

    func unregisterAll() {}
}
