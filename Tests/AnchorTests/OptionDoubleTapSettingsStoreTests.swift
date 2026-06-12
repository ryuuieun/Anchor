import XCTest
@testable import Anchor

final class OptionDoubleTapSettingsStoreTests: XCTestCase {
    func testDefaultsToEnabledWhenNoPersistedSettingExists() {
        let store = OptionDoubleTapSettingsStore(userDefaults: makeUserDefaults())

        XCTAssertTrue(store.isEnabled)
    }

    func testSetEnabledPersistsSetting() {
        let defaults = makeUserDefaults()
        let store = OptionDoubleTapSettingsStore(userDefaults: defaults)

        store.setEnabled(false)

        let reloadedStore = OptionDoubleTapSettingsStore(userDefaults: defaults)
        XCTAssertFalse(reloadedStore.isEnabled)
    }

    func testCanReenablePersistedSetting() {
        let defaults = makeUserDefaults()
        let store = OptionDoubleTapSettingsStore(userDefaults: defaults)
        store.setEnabled(false)

        store.setEnabled(true)

        let reloadedStore = OptionDoubleTapSettingsStore(userDefaults: defaults)
        XCTAssertTrue(reloadedStore.isEnabled)
    }
}
