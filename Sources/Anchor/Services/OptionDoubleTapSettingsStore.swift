import Foundation
import os

private let optionDoubleTapSettingsLogger = AnchorLog.settings

final class OptionDoubleTapSettingsStore: ObservableObject {
    private let userDefaults: UserDefaults
    private let storageKey: String

    @Published private(set) var isEnabled: Bool

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "OptionDoubleTapBindingEnabled.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        isEnabled = userDefaults.object(forKey: storageKey) as? Bool ?? true
        optionDoubleTapSettingsLogger.info("Loaded Option double-tap binding setting: enabled=\(self.isEnabled)")
    }

    func setEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else {
            return
        }

        self.isEnabled = isEnabled
        userDefaults.set(isEnabled, forKey: storageKey)
        optionDoubleTapSettingsLogger.info("Updated Option double-tap binding setting: enabled=\(isEnabled)")
    }
}
