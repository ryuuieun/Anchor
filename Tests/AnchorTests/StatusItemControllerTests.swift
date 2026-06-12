import AppKit
import XCTest
@testable import Anchor

final class StatusItemControllerTests: XCTestCase {
    @MainActor
    func testMenuWillOpenDoesNotRebuildVisibleMenuWhenStateIsUnchanged() {
        let windowService = StatusMenuMockWindowService()
        let slotStore = WindowSlotStore(
            slotIDs: [1],
            windowService: windowService,
            focusService: StatusMenuMockWindowFocusService(),
            lifecycleObserver: StatusMenuMockWindowLifecycleObserver()
        )
        let hotKeyManager = HotKeyManager(
            slotIDs: [1],
            registrar: StatusMenuMockHotKeyRegistrar()
        )
        let controller = StatusItemController(
            permissionService: AccessibilityPermissionService(),
            windowService: windowService,
            slotStore: slotStore,
            hotKeyManager: hotKeyManager,
            optionDoubleTapSettingsStore: OptionDoubleTapSettingsStore(userDefaults: makeUserDefaults()),
            slotBindingPopupPresenter: StatusMenuMockSlotBindingPopupPresenter(),
            modifierDoubleTapMonitor: StatusMenuMockModifierDoubleTapMonitor()
        )
        let initialItems = controller.menuForTesting.items.map(ObjectIdentifier.init)

        controller.menuWillOpen(controller.menuForTesting)

        XCTAssertEqual(controller.menuForTesting.items.map(ObjectIdentifier.init), initialItems)
    }

    @MainActor
    func testMenuOpenStatusRefreshDefersVisibleMenuRebuildUntilClose() {
        let windowService = StatusMenuMockWindowService()
        let focusService = StatusMenuMockWindowFocusService()
        let lifecycleObserver = StatusMenuMockWindowLifecycleObserver()
        let slotStore = WindowSlotStore(
            slotIDs: [1],
            windowService: windowService,
            focusService: focusService,
            lifecycleObserver: lifecycleObserver
        )
        let window = makeStatusMenuWindow()
        windowService.captureResults = [.success(window)]
        slotStore.bindFocusedWindow(to: 1)

        let hotKeyManager = HotKeyManager(
            slotIDs: [1],
            registrar: StatusMenuMockHotKeyRegistrar()
        )
        let controller = StatusItemController(
            permissionService: AccessibilityPermissionService(),
            windowService: windowService,
            slotStore: slotStore,
            hotKeyManager: hotKeyManager,
            optionDoubleTapSettingsStore: OptionDoubleTapSettingsStore(userDefaults: makeUserDefaults()),
            slotBindingPopupPresenter: StatusMenuMockSlotBindingPopupPresenter(),
            modifierDoubleTapMonitor: StatusMenuMockModifierDoubleTapMonitor()
        )

        XCTAssertTrue(controller.menuTitlesForTesting.contains { $0.contains("Slot 1:") })
        XCTAssertFalse(controller.menuTitlesForTesting.contains("Anchor"))
        XCTAssertFalse(controller.menuTitlesForTesting.contains { $0.hasPrefix("Accessibility:") })
        XCTAssertFalse(controller.menuTitlesForTesting.contains("Bound slot 1 to Test App - Window"))
        XCTAssertFalse(controller.menuTitlesForTesting.contains("Hotkeys not registered"))

        windowService.validationResults[ObjectIdentifier(window)] = .missing("window closed")
        let refreshApplied = expectation(description: "menu status refresh")
        controller.onMenuStatusRefreshAppliedForTesting = {
            refreshApplied.fulfill()
        }

        controller.menuWillOpen(controller.menuForTesting)

        wait(for: [refreshApplied], timeout: 1)

        XCTAssertTrue(controller.menuTitlesForTesting.contains { $0.contains("Slot 1:") })
        XCTAssertEqual(slotStore.slots.first?.status, .empty)
        XCTAssertNil(slotStore.slots.first?.window)
        XCTAssertFalse(windowService.didValidateOnMainThread)

        controller.menuDidClose(controller.menuForTesting)

        XCTAssertFalse(controller.menuTitlesForTesting.contains { $0.contains("Slot 1:") })
    }

    @MainActor
    func testOptionDoubleTapCapturesFocusedWindowAndShowsBindingPopupWithoutBinding() {
        let windowService = StatusMenuMockWindowService()
        let slotStore = WindowSlotStore(
            slotIDs: [1, 2],
            windowService: windowService,
            focusService: StatusMenuMockWindowFocusService(),
            lifecycleObserver: StatusMenuMockWindowLifecycleObserver()
        )
        let hotKeyManager = HotKeyManager(
            slotIDs: [1, 2],
            registrar: StatusMenuMockHotKeyRegistrar()
        )
        let popupPresenter = StatusMenuMockSlotBindingPopupPresenter()
        let doubleTapMonitor = StatusMenuMockModifierDoubleTapMonitor()
        let window = makeStatusMenuWindow()
        windowService.captureResults = [.success(window)]

        let controller = StatusItemController(
            permissionService: AccessibilityPermissionService(),
            windowService: windowService,
            slotStore: slotStore,
            hotKeyManager: hotKeyManager,
            optionDoubleTapSettingsStore: OptionDoubleTapSettingsStore(userDefaults: makeUserDefaults()),
            slotBindingPopupPresenter: popupPresenter,
            modifierDoubleTapMonitor: doubleTapMonitor
        )

        doubleTapMonitor.trigger()

        XCTAssertEqual(popupPresenter.presentations.count, 1)
        XCTAssertTrue(popupPresenter.presentations.first?.window === window)
        XCTAssertEqual(popupPresenter.presentations.first?.slots.map(\.id), [1, 2])
        XCTAssertTrue(slotStore.slots.allSatisfy { $0.window == nil })
        XCTAssertTrue(doubleTapMonitor.didStart)
        withExtendedLifetime(controller) {}
    }

    @MainActor
    func testOptionDoubleTapDoesNotShowPopupWhenCaptureFails() {
        let windowService = StatusMenuMockWindowService()
        let slotStore = WindowSlotStore(
            slotIDs: [1],
            windowService: windowService,
            focusService: StatusMenuMockWindowFocusService(),
            lifecycleObserver: StatusMenuMockWindowLifecycleObserver()
        )
        let hotKeyManager = HotKeyManager(
            slotIDs: [1],
            registrar: StatusMenuMockHotKeyRegistrar()
        )
        let popupPresenter = StatusMenuMockSlotBindingPopupPresenter()
        let doubleTapMonitor = StatusMenuMockModifierDoubleTapMonitor()
        windowService.captureResults = [.failure("no focused window")]

        let controller = StatusItemController(
            permissionService: AccessibilityPermissionService(),
            windowService: windowService,
            slotStore: slotStore,
            hotKeyManager: hotKeyManager,
            optionDoubleTapSettingsStore: OptionDoubleTapSettingsStore(userDefaults: makeUserDefaults()),
            slotBindingPopupPresenter: popupPresenter,
            modifierDoubleTapMonitor: doubleTapMonitor
        )

        doubleTapMonitor.trigger()

        XCTAssertTrue(popupPresenter.presentations.isEmpty)
        XCTAssertEqual(slotStore.lastMessage, "Could not capture window for binding: no focused window")
        withExtendedLifetime(controller) {}
    }

    @MainActor
    func testDisabledOptionDoubleTapSettingStopsMonitorAndIgnoresTrigger() {
        let windowService = StatusMenuMockWindowService()
        let slotStore = WindowSlotStore(
            slotIDs: [1],
            windowService: windowService,
            focusService: StatusMenuMockWindowFocusService(),
            lifecycleObserver: StatusMenuMockWindowLifecycleObserver()
        )
        let hotKeyManager = HotKeyManager(
            slotIDs: [1],
            registrar: StatusMenuMockHotKeyRegistrar()
        )
        let popupPresenter = StatusMenuMockSlotBindingPopupPresenter()
        let doubleTapMonitor = StatusMenuMockModifierDoubleTapMonitor()
        let settingsStore = OptionDoubleTapSettingsStore(userDefaults: makeUserDefaults())
        settingsStore.setEnabled(false)
        windowService.captureResults = [.success(makeStatusMenuWindow())]

        let controller = StatusItemController(
            permissionService: AccessibilityPermissionService(),
            windowService: windowService,
            slotStore: slotStore,
            hotKeyManager: hotKeyManager,
            optionDoubleTapSettingsStore: settingsStore,
            slotBindingPopupPresenter: popupPresenter,
            modifierDoubleTapMonitor: doubleTapMonitor
        )

        doubleTapMonitor.trigger()

        XCTAssertEqual(doubleTapMonitor.startCount, 0)
        XCTAssertEqual(doubleTapMonitor.stopCount, 1)
        XCTAssertEqual(windowService.captureCount, 0)
        XCTAssertTrue(popupPresenter.presentations.isEmpty)
        withExtendedLifetime(controller) {}
    }

    @MainActor
    func testOptionDoubleTapSettingChangeStopsAndRestartsMonitor() {
        let windowService = StatusMenuMockWindowService()
        let slotStore = WindowSlotStore(
            slotIDs: [1],
            windowService: windowService,
            focusService: StatusMenuMockWindowFocusService(),
            lifecycleObserver: StatusMenuMockWindowLifecycleObserver()
        )
        let hotKeyManager = HotKeyManager(
            slotIDs: [1],
            registrar: StatusMenuMockHotKeyRegistrar()
        )
        let doubleTapMonitor = StatusMenuMockModifierDoubleTapMonitor()
        let settingsStore = OptionDoubleTapSettingsStore(userDefaults: makeUserDefaults())

        let controller = StatusItemController(
            permissionService: AccessibilityPermissionService(),
            windowService: windowService,
            slotStore: slotStore,
            hotKeyManager: hotKeyManager,
            optionDoubleTapSettingsStore: settingsStore,
            slotBindingPopupPresenter: StatusMenuMockSlotBindingPopupPresenter(),
            modifierDoubleTapMonitor: doubleTapMonitor
        )

        settingsStore.setEnabled(false)
        settingsStore.setEnabled(true)

        XCTAssertEqual(doubleTapMonitor.startCount, 2)
        XCTAssertEqual(doubleTapMonitor.stopCount, 1)
        withExtendedLifetime(controller) {}
    }
}

private final class StatusMenuMockWindowService: WindowServiceProtocol {
    var captureResults: [WindowCaptureResult] = []
    var validationResults: [ObjectIdentifier: WindowValidationResult] = [:]
    private(set) var captureCount = 0
    private let lock = NSLock()
    private var validationThreadWasMain: Bool?

    var didValidateOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return validationThreadWasMain ?? true
    }

    func captureFocusedWindow() -> WindowCaptureResult {
        captureCount += 1
        guard !captureResults.isEmpty else {
            return .failure("no capture result configured")
        }
        return captureResults.removeFirst()
    }

    func validate(_ window: WindowReference) -> WindowValidationResult {
        lock.lock()
        validationThreadWasMain = Thread.isMainThread
        lock.unlock()
        return validationResults[ObjectIdentifier(window)] ?? .valid
    }

    func refreshFingerprint(for window: WindowReference) {}

    func focusedWindowMatches(_ window: WindowReference) -> Bool {
        false
    }
}

private final class StatusMenuMockWindowFocusService: WindowFocusServiceProtocol {
    func focus(_ window: WindowReference, completion: @escaping (WindowActionResult) -> Void) {
        completion(.focused)
    }
}

private final class StatusMenuMockWindowLifecycleObserver: WindowLifecycleObserving {
    var onWindowInvalidated: ((WindowReference, String) -> Void)?

    func watch(_ window: WindowReference, slotID: Int) -> WindowLifecycleWatchResult {
        .observing
    }

    func unwatchSlot(_ slotID: Int) {}

    func unwatchAll() {}
}

private final class StatusMenuMockHotKeyRegistrar: HotKeyRegistrar {
    func register(_ definitions: [HotKeyDefinition], handler: @escaping (HotKeyIntent) -> Void) throws {}

    func unregisterAll() {}
}

private final class StatusMenuMockSlotBindingPopupPresenter: SlotBindingPopupPresenting {
    struct Presentation {
        let window: WindowReference
        let slots: [WindowSlot]
    }

    private(set) var presentations: [Presentation] = []

    func show(for window: WindowReference, slots: [WindowSlot]) {
        presentations.append(Presentation(window: window, slots: slots))
    }
}

private final class StatusMenuMockModifierDoubleTapMonitor: ModifierDoubleTapMonitoring {
    var onDoubleTap: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    var didStart: Bool {
        startCount > 0
    }

    var didStop: Bool {
        stopCount > 0
    }

    @discardableResult
    func start() -> Bool {
        startCount += 1
        return true
    }

    func stop() {
        stopCount += 1
    }

    func trigger() {
        onDoubleTap?()
    }
}

private final class StatusMenuTestWindowHandle: WindowElementHandle {
    let id: Int

    init(id: Int) {
        self.id = id
    }

    func isSameWindow(as other: WindowElementHandle) -> Bool {
        guard let other = other as? StatusMenuTestWindowHandle else {
            return false
        }
        return id == other.id
    }
}

private func makeStatusMenuWindow(
    pid: pid_t = 10_000,
    appName: String = "Test App",
    bundleIdentifier: String = "dev.test.App",
    title: String = "Window"
) -> WindowReference {
    let fingerprint = WindowFingerprint(
        pid: pid,
        bundleIdentifier: bundleIdentifier,
        title: title,
        role: "AXWindow",
        subrole: "AXStandardWindow",
        identifier: nil,
        position: nil,
        size: nil,
        cgWindowID: nil,
        cgBounds: nil,
        cgLayer: nil
    )

    return WindowReference(
        handle: StatusMenuTestWindowHandle(id: Int(pid)),
        pid: pid,
        appName: appName,
        bundleIdentifier: bundleIdentifier,
        bundleURL: nil,
        title: title,
        role: "AXWindow",
        subrole: "AXStandardWindow",
        identifier: nil,
        fingerprint: fingerprint
    )
}
