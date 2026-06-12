import AppKit
import XCTest
@testable import Anchor

final class SlotBindingPopupControllerTests: XCTestCase {
    @MainActor
    func testPreparedPopupMenuIncludesBoundAndEmptySlots() {
        let environment = SlotBindingPopupTestEnvironment(slotIDs: [1, 2])
        let existingWindow = makePopupTestWindow(pid: 10_001, title: "Existing")
        environment.store.bindWindow(existingWindow, to: 1)

        let controller = SlotBindingPopupController(slotStore: environment.store)
        let capturedWindow = makePopupTestWindow(pid: 10_002, title: "Captured")
        let menu = controller.prepareMenuForTesting(
            for: capturedWindow,
            slots: environment.store.slots
        )

        XCTAssertEqual(menu.items.map(\.title), ["Slot 1 - Test App - Existing", "Slot 2"])
        XCTAssertTrue(controller.pendingWindowForTesting === capturedWindow)
    }

    @MainActor
    func testSelectingPopupSlotBindsCapturedWindow() {
        let environment = SlotBindingPopupTestEnvironment(slotIDs: [1, 2])
        let controller = SlotBindingPopupController(slotStore: environment.store)
        let capturedWindow = makePopupTestWindow(pid: 10_003, title: "Captured")
        _ = controller.prepareMenuForTesting(for: capturedWindow, slots: environment.store.slots)

        controller.bindSlotForTesting(2)

        XCTAssertTrue(environment.store.slots.first { $0.id == 2 }?.window === capturedWindow)
        XCTAssertNil(controller.pendingWindowForTesting)
    }

    @MainActor
    func testMenuCloseBeforeActionStillAllowsPendingSelectionToBind() {
        let environment = SlotBindingPopupTestEnvironment(slotIDs: [1, 2])
        let controller = SlotBindingPopupController(slotStore: environment.store)
        let capturedWindow = makePopupTestWindow(pid: 10_004, title: "Captured")
        let menu = controller.prepareMenuForTesting(for: capturedWindow, slots: environment.store.slots)

        controller.menuDidClose(menu)
        controller.bindSlotForTesting(2)

        XCTAssertTrue(environment.store.slots.first { $0.id == 2 }?.window === capturedWindow)
        XCTAssertNil(controller.pendingWindowForTesting)
    }

    @MainActor
    func testMenuCloseWithoutSelectionClearsPendingWindow() {
        let environment = SlotBindingPopupTestEnvironment(slotIDs: [1, 2])
        let controller = SlotBindingPopupController(slotStore: environment.store)
        let capturedWindow = makePopupTestWindow(pid: 10_005, title: "Captured")
        let menu = controller.prepareMenuForTesting(for: capturedWindow, slots: environment.store.slots)

        controller.menuDidClose(menu)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        XCTAssertNil(controller.pendingWindowForTesting)
    }
}

private final class SlotBindingPopupTestEnvironment {
    let store: WindowSlotStore

    init(slotIDs: [Int]) {
        store = WindowSlotStore(
            slotIDs: slotIDs,
            windowService: SlotBindingPopupMockWindowService(),
            focusService: SlotBindingPopupMockWindowFocusService(),
            lifecycleObserver: SlotBindingPopupMockWindowLifecycleObserver()
        )
    }
}

private final class SlotBindingPopupMockWindowService: WindowServiceProtocol {
    func captureFocusedWindow() -> WindowCaptureResult {
        .failure("not configured")
    }

    func validate(_ window: WindowReference) -> WindowValidationResult {
        .valid
    }

    func refreshFingerprint(for window: WindowReference) {}

    func focusedWindowMatches(_ window: WindowReference) -> Bool {
        false
    }
}

private final class SlotBindingPopupMockWindowFocusService: WindowFocusServiceProtocol {
    func focus(_ window: WindowReference, completion: @escaping (WindowActionResult) -> Void) {
        completion(.focused)
    }
}

private final class SlotBindingPopupMockWindowLifecycleObserver: WindowLifecycleObserving {
    var onWindowInvalidated: ((WindowReference, String) -> Void)?

    func watch(_ window: WindowReference, slotID: Int) -> WindowLifecycleWatchResult {
        .observing
    }

    func unwatchSlot(_ slotID: Int) {}

    func unwatchAll() {}
}

private final class SlotBindingPopupTestWindowHandle: WindowElementHandle {
    let id: Int

    init(id: Int) {
        self.id = id
    }

    func isSameWindow(as other: WindowElementHandle) -> Bool {
        guard let other = other as? SlotBindingPopupTestWindowHandle else {
            return false
        }
        return id == other.id
    }
}

private func makePopupTestWindow(
    pid: pid_t,
    appName: String = "Test App",
    bundleIdentifier: String = "dev.test.App",
    title: String
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
        handle: SlotBindingPopupTestWindowHandle(id: Int(pid)),
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
