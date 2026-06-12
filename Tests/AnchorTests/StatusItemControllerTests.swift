import AppKit
import XCTest
@testable import Anchor

final class StatusItemControllerTests: XCTestCase {
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
            slotStore: slotStore,
            hotKeyManager: hotKeyManager
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
}

private final class StatusMenuMockWindowService: WindowServiceProtocol {
    var captureResults: [WindowCaptureResult] = []
    var validationResults: [ObjectIdentifier: WindowValidationResult] = [:]
    private let lock = NSLock()
    private var validationThreadWasMain: Bool?

    var didValidateOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return validationThreadWasMain ?? true
    }

    func captureFocusedWindow() -> WindowCaptureResult {
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
