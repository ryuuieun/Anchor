import XCTest
@testable import Anchor

final class WindowSlotStoreTests: XCTestCase {
    func testBindFailureLeavesSlotEmpty() {
        let environment = TestEnvironment(slotIDs: [1])
        environment.windowService.captureResults = [.failure("no focused window")]

        environment.store.bindFocusedWindow(to: 1)

        XCTAssertNil(environment.store.slot(1).window)
        XCTAssertEqual(environment.store.slot(1).status, .empty)
        XCTAssertEqual(environment.store.lastMessage, "Could not bind slot 1: no focused window")
        XCTAssertTrue(environment.lifecycleObserver.watchedSlots.isEmpty)
    }

    func testBindToUnknownSlotDoesNotWatchWindow() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = makeWindow()
        environment.windowService.captureResults = [.success(window)]

        environment.store.bindFocusedWindow(to: 9)

        XCTAssertNil(environment.store.slot(1).window)
        XCTAssertEqual(environment.store.lastMessage, "Unknown slot 9")
        XCTAssertTrue(environment.lifecycleObserver.watchedSlots.isEmpty)
    }

    func testBindToUnknownSlotKeepsExistingBindingForSameWindow() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = makeWindow()
        environment.windowService.captureResults = [.success(window)]
        environment.store.bindFocusedWindow(to: 1)
        environment.windowService.captureResults = [.success(window)]

        environment.store.bindFocusedWindow(to: 9)

        XCTAssertTrue(environment.store.slot(1).window === window)
        XCTAssertEqual(environment.store.slot(1).status, .active)
        XCTAssertEqual(environment.store.lastMessage, "Unknown slot 9")
        XCTAssertTrue(environment.lifecycleObserver.watchedSlots[1] === window)
        XCTAssertTrue(environment.lifecycleObserver.unwatchedSlots.isEmpty)
        XCTAssertEqual(environment.windowService.captureResults.count, 1)
    }

    func testBindingSameWindowToNewSlotClearsOldSlot() {
        let environment = TestEnvironment(slotIDs: [1, 2])
        let window = makeWindow(title: "Notes")
        environment.windowService.captureResults = [.success(window), .success(window)]

        environment.store.bindFocusedWindow(to: 1)
        environment.store.bindFocusedWindow(to: 2)

        XCTAssertNil(environment.store.slot(1).window)
        XCTAssertTrue(environment.store.slot(2).window === window)
        XCTAssertEqual(environment.store.slot(1).status, .empty)
        XCTAssertEqual(environment.store.slot(2).status, .active)
        XCTAssertEqual(environment.lifecycleObserver.unwatchedSlots, [1])
        XCTAssertTrue(environment.lifecycleObserver.watchedSlots[2] === window)
    }

    func testLifecycleFallbackMessageIncludesReason() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = makeWindow()
        environment.lifecycleObserver.watchResult = .appTerminationOnly("AXObserverCreate failure")
        environment.windowService.captureResults = [.success(window)]

        environment.store.bindFocusedWindow(to: 1)

        XCTAssertTrue(environment.store.slot(1).window === window)
        XCTAssertEqual(
            environment.store.lastMessage,
            "Bound slot 1 to Test App - Window (close listener unavailable: AXObserverCreate failure)"
        )
    }

    func testActivateUnknownSlotUpdatesMessage() {
        let environment = TestEnvironment(slotIDs: [1])

        environment.store.activate(slotID: 9)

        XCTAssertEqual(environment.store.lastMessage, "Unknown slot 9")
    }

    func testActivateEmptySlotKeepsSlotEmpty() {
        let environment = TestEnvironment(slotIDs: [1])

        environment.store.activate(slotID: 1)

        XCTAssertNil(environment.store.slot(1).window)
        XCTAssertEqual(environment.store.slot(1).status, .empty)
        XCTAssertEqual(environment.store.lastMessage, "Slot 1 is empty")
    }

    func testActivatingFocusedWindowDoesNotMinimizeOrFocusAgain() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid
        environment.windowService.focusedWindowIDs.insert(ObjectIdentifier(window))

        environment.store.activate(slotID: 1)

        XCTAssertTrue(environment.focusService.focusedWindows.isEmpty)
        XCTAssertEqual(environment.store.slot(1).status, .active)
        XCTAssertEqual(environment.store.lastMessage, "Slot 1: Focused window")
        XCTAssertTrue(environment.windowService.refreshedWindows.isEmpty)
    }

    func testUpdatedFingerprintValidationStillFocusesWindow() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .updatedFingerprint
        environment.focusService.focusResult = .focused

        environment.store.activate(slotID: 1)

        XCTAssertEqual(environment.focusService.focusedWindows.count, 1)
        XCTAssertTrue(environment.focusService.focusedWindows.first === window)
        XCTAssertEqual(environment.store.slot(1).status, .active)
    }

    func testUpdatedFingerprintValidationRewatchesWindowLifecycle() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .updatedFingerprint

        environment.store.activate(slotID: 1)

        XCTAssertEqual(environment.lifecycleObserver.unwatchedSlots, [1])
        XCTAssertEqual(environment.lifecycleObserver.watchEvents, [1, 1])
        XCTAssertTrue(environment.lifecycleObserver.watchedSlots[1] === window)
    }

    func testFocusFailureMarksActionFailed() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid
        environment.focusService.focusResult = .failed("focus failed")

        environment.store.activate(slotID: 1)

        XCTAssertEqual(environment.store.slot(1).status, .actionFailed("focus failed"))
        XCTAssertEqual(environment.store.lastMessage, "Slot 1: focus failed")
        XCTAssertTrue(environment.windowService.refreshedWindows.isEmpty)
    }

    func testActivatingNonFocusedWindowCallsFocus() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid
        environment.focusService.focusResult = .focused

        environment.store.activate(slotID: 1)

        XCTAssertEqual(environment.focusService.focusedWindows.count, 1)
        XCTAssertTrue(environment.focusService.focusedWindows.first === window)
        XCTAssertEqual(environment.store.slot(1).status, .active)
        XCTAssertEqual(environment.store.lastMessage, "Slot 1: Focused window")
        XCTAssertEqual(environment.windowService.refreshedWindows.count, 1)
        XCTAssertTrue(environment.windowService.refreshedWindows.first === window)
    }

    func testRepeatedActivationWhileFocusIsRunningStartsEveryRequestImmediately() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid
        environment.focusService.completesFocusImmediately = false

        environment.store.activate(slotID: 1)
        environment.store.activate(slotID: 1)
        environment.store.activate(slotID: 1)

        XCTAssertEqual(environment.focusService.focusedWindows.count, 3)
        XCTAssertTrue(environment.focusService.focusedWindows.allSatisfy { $0 === window })
        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 3)
        XCTAssertEqual(environment.store.lastMessage, "Slot 1: switching to Test App - Window")

        environment.focusService.completeNextFocus()
        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 2)

        environment.focusService.completeNextFocus()
        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 1)

        environment.focusService.completeNextFocus()
        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 0)
        XCTAssertEqual(environment.store.slot(1).status, .active)
    }

    func testOlderFocusCompletionCannotOverwriteNewerResultForSameWindow() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid
        environment.focusService.completesFocusImmediately = false

        environment.store.activate(slotID: 1)
        environment.store.activate(slotID: 1)

        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 2)

        environment.focusService.completeFocus(at: 1, with: .focused)
        XCTAssertEqual(environment.store.slot(1).status, .active)

        environment.focusService.completeFocus(at: 0, with: .failed("old focus failed"))

        XCTAssertEqual(environment.store.slot(1).status, .active)
        XCTAssertEqual(environment.store.lastMessage, "Slot 1: Focused window")
    }

    func testActivationValidationFailureInvalidatesOlderPendingFocusCompletion() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid
        environment.focusService.completesFocusImmediately = false

        environment.store.activate(slotID: 1)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .temporarilyUnavailable("AX cannot complete")
        environment.store.activate(slotID: 1)

        XCTAssertEqual(environment.store.slot(1).status, .unavailable("AX cannot complete"))
        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 1)

        environment.focusService.completeNextFocus(with: .focused)

        XCTAssertEqual(environment.store.slot(1).status, .unavailable("AX cannot complete"))
        XCTAssertEqual(environment.store.lastMessage, "Slot 1 temporarily unavailable: AX cannot complete")
    }

    func testRepeatedFocusedWindowActivationDoesNotFocusAgain() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid
        environment.windowService.focusedWindowIDs.insert(ObjectIdentifier(window))

        environment.store.activate(slotID: 1)
        environment.store.activate(slotID: 1)
        environment.store.activate(slotID: 1)

        XCTAssertTrue(environment.focusService.focusedWindows.isEmpty)
        XCTAssertEqual(environment.store.lastMessage, "Slot 1: Focused window")
        XCTAssertTrue(environment.windowService.refreshedWindows.isEmpty)
    }

    func testRepeatedActivationAfterImmediateFocusRunsEachRequest() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid

        environment.store.activate(slotID: 1)
        environment.store.activate(slotID: 1)
        environment.store.activate(slotID: 1)

        XCTAssertEqual(environment.focusService.focusedWindows.count, 3)
        XCTAssertTrue(environment.focusService.focusedWindows.allSatisfy { $0 === window })
        XCTAssertEqual(environment.store.slot(1).status, .active)
    }

    func testRepeatedActivationDoesNotBlockOtherSlots() {
        let environment = TestEnvironment(slotIDs: [1, 2])
        let firstWindow = bind(window: makeWindow(pid: 10_000, handleID: 1), to: 1, in: environment)
        let secondWindow = bind(window: makeWindow(pid: 10_001, handleID: 2), to: 2, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(firstWindow)] = .valid
        environment.windowService.validationResults[ObjectIdentifier(secondWindow)] = .valid
        environment.focusService.completesFocusImmediately = false

        environment.store.activate(slotID: 1)
        environment.store.activate(slotID: 1)
        environment.store.activate(slotID: 2)

        XCTAssertEqual(environment.focusService.focusedWindows.count, 3)
        XCTAssertTrue(environment.focusService.focusedWindows[0] === firstWindow)
        XCTAssertTrue(environment.focusService.focusedWindows[1] === firstWindow)
        XCTAssertTrue(environment.focusService.focusedWindows[2] === secondWindow)
        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 3)
    }

    func testRepeatedFocusFailureRunsEachActivation() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid
        environment.focusService.focusResult = .failed("focus failed")

        environment.store.activate(slotID: 1)
        environment.store.activate(slotID: 1)

        XCTAssertEqual(environment.focusService.focusedWindows.count, 2)
        XCTAssertEqual(environment.store.slot(1).status, .actionFailed("focus failed"))
    }

    func testClearingSlotWhileFocusCompletionIsPendingIgnoresLateResult() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid
        environment.focusService.completesFocusImmediately = false

        environment.store.activate(slotID: 1)
        environment.store.activate(slotID: 1)
        environment.store.clear(slotID: 1)
        environment.focusService.completeNextFocus()

        XCTAssertNil(environment.store.slot(1).window)
        XCTAssertEqual(environment.store.slot(1).status, .empty)
        XCTAssertEqual(environment.store.lastMessage, "Cleared slot 1")
        XCTAssertEqual(environment.focusService.focusedWindows.count, 2)
        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 1)
    }

    func testLateFocusCompletionAfterRebindDoesNotOverwriteNewBinding() {
        let environment = TestEnvironment(slotIDs: [1])
        let oldWindow = bind(window: makeWindow(pid: 10_000, handleID: 1), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(oldWindow)] = .valid
        environment.focusService.completesFocusImmediately = false

        environment.store.activate(slotID: 1)

        XCTAssertEqual(environment.focusService.focusedWindows.count, 1)
        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 1)

        let newWindow = bind(window: makeWindow(pid: 10_001, title: "New Window", handleID: 2), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(newWindow)] = .valid

        environment.store.activate(slotID: 1)

        XCTAssertEqual(environment.focusService.focusedWindows.count, 2)
        XCTAssertTrue(environment.focusService.focusedWindows[1] === newWindow)
        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 2)
        XCTAssertEqual(environment.store.lastMessage, "Slot 1: switching to Test App - New Window")

        environment.focusService.completeNextFocus()

        XCTAssertTrue(environment.store.slot(1).window === newWindow)
        XCTAssertEqual(environment.store.slot(1).status, .switching)
        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 1)

        environment.focusService.completeNextFocus()

        XCTAssertTrue(environment.store.slot(1).window === newWindow)
        XCTAssertEqual(environment.store.slot(1).status, .active)
        XCTAssertEqual(environment.focusService.pendingFocusCompletionCount, 0)
    }

    func testMissingValidationClearsSlot() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .missing("window closed")

        environment.store.activate(slotID: 1)

        XCTAssertNil(environment.store.slot(1).window)
        XCTAssertEqual(environment.store.slot(1).status, .empty)
        XCTAssertEqual(environment.store.lastMessage, "Cleared slot 1: window closed")
        XCTAssertEqual(environment.lifecycleObserver.unwatchedSlots, [1])
    }

    func testTemporaryValidationFailureKeepsSlot() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .temporarilyUnavailable("AX cannot complete")

        environment.store.activate(slotID: 1)

        XCTAssertTrue(environment.store.slot(1).window === window)
        XCTAssertEqual(environment.store.slot(1).status, .unavailable("AX cannot complete"))
        XCTAssertEqual(environment.store.lastMessage, "Slot 1 temporarily unavailable: AX cannot complete")
    }

    func testAccessibilityValidationFailureKeepsSlotAndDoesNotFocus() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .accessibilityUnavailable(
            "Accessibility permission is required (accessibility API disabled)"
        )

        environment.store.activate(slotID: 1)

        XCTAssertTrue(environment.store.slot(1).window === window)
        XCTAssertEqual(environment.store.slot(1).status, .accessibilityUnavailable(
            "Accessibility permission is required (accessibility API disabled)"
        ))
        XCTAssertEqual(
            environment.store.lastMessage,
            "Slot 1 accessibility unavailable: Accessibility permission is required (accessibility API disabled)"
        )
        XCTAssertTrue(environment.focusService.focusedWindows.isEmpty)
        XCTAssertTrue(environment.lifecycleObserver.unwatchedSlots.isEmpty)
    }

    func testUnavailableSlotBecomesActiveAgainOnRefreshWhenValidationRecovers() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .temporarilyUnavailable("AX cannot complete")
        environment.store.refreshStatuses()

        XCTAssertEqual(environment.store.slot(1).status, .unavailable("AX cannot complete"))

        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid
        environment.store.refreshStatuses()

        XCTAssertEqual(environment.store.slot(1).status, .active)
    }

    func testAccessibilityUnavailableSlotBecomesActiveAgainOnRefreshWhenValidationRecovers() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .accessibilityUnavailable(
            "Accessibility permission is required (accessibility API disabled)"
        )
        environment.store.refreshStatuses()

        XCTAssertEqual(environment.store.slot(1).status, .accessibilityUnavailable(
            "Accessibility permission is required (accessibility API disabled)"
        ))

        environment.windowService.validationResults[ObjectIdentifier(window)] = .valid
        environment.store.refreshStatuses()

        XCTAssertEqual(environment.store.slot(1).status, .active)
    }

    func testRefreshStatusesRewatchesLifecycleWhenFingerprintUpdates() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .updatedFingerprint

        environment.store.refreshStatuses()

        XCTAssertEqual(environment.lifecycleObserver.unwatchedSlots, [1])
        XCTAssertEqual(environment.lifecycleObserver.watchEvents, [1, 1])
        XCTAssertTrue(environment.lifecycleObserver.watchedSlots[1] === window)
        XCTAssertEqual(environment.store.slot(1).status, .active)
    }

    func testRewatchFallbackKeepsUpdatedWindowBound() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.lifecycleObserver.watchResult = .appTerminationOnly("AXObserverCreate failure")
        environment.windowService.validationResults[ObjectIdentifier(window)] = .updatedFingerprint

        environment.store.refreshStatuses()

        XCTAssertTrue(environment.store.slot(1).window === window)
        XCTAssertEqual(environment.store.slot(1).status, .active)
        XCTAssertEqual(
            environment.store.lastMessage,
            "Slot 1: close listener unavailable after window refresh: AXObserverCreate failure"
        )
    }

    func testLifecycleInvalidationClearsMatchingSlot() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)

        environment.lifecycleObserver.invalidate(window, reason: "window closed")

        XCTAssertNil(environment.store.slot(1).window)
        XCTAssertEqual(environment.store.slot(1).status, .empty)
        XCTAssertEqual(environment.store.lastMessage, "Cleared slot 1: window closed")
        XCTAssertEqual(environment.lifecycleObserver.unwatchedSlots, [1])
    }

    func testLifecycleInvalidationIgnoresOtherWindows() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(pid: 10_000), to: 1, in: environment)
        let otherWindow = makeWindow(pid: 10_001)

        environment.lifecycleObserver.invalidate(otherWindow, reason: "window closed")

        XCTAssertTrue(environment.store.slot(1).window === window)
        XCTAssertEqual(environment.store.slot(1).status, .active)
        XCTAssertEqual(environment.store.lastMessage, "Bound slot 1 to Test App - Window")
    }

    func testRefreshStatusesClearsAmbiguousSlot() {
        let environment = TestEnvironment(slotIDs: [1])
        let window = bind(window: makeWindow(), to: 1, in: environment)
        environment.windowService.validationResults[ObjectIdentifier(window)] = .ambiguous("window identity ambiguous")

        environment.store.refreshStatuses()

        XCTAssertNil(environment.store.slot(1).window)
        XCTAssertEqual(environment.store.slot(1).status, .empty)
        XCTAssertEqual(environment.store.lastMessage, "Cleared slot 1: window identity ambiguous")
    }

    func testClearSlotRemovesBindingAndUnwatches() {
        let environment = TestEnvironment(slotIDs: [1])
        _ = bind(window: makeWindow(), to: 1, in: environment)

        environment.store.clear(slotID: 1)

        XCTAssertNil(environment.store.slot(1).window)
        XCTAssertEqual(environment.store.slot(1).status, .empty)
        XCTAssertEqual(environment.lifecycleObserver.unwatchedSlots, [1])
        XCTAssertEqual(environment.store.lastMessage, "Cleared slot 1")
    }

    func testClearAllRemovesEveryBinding() {
        let environment = TestEnvironment(slotIDs: [1, 2])
        _ = bind(window: makeWindow(pid: 10_000), to: 1, in: environment)
        _ = bind(window: makeWindow(pid: 10_001), to: 2, in: environment)

        environment.store.clearAll()

        XCTAssertNil(environment.store.slot(1).window)
        XCTAssertNil(environment.store.slot(2).window)
        XCTAssertEqual(environment.store.slot(1).status, .empty)
        XCTAssertEqual(environment.store.slot(2).status, .empty)
        XCTAssertTrue(environment.lifecycleObserver.didUnwatchAll)
        XCTAssertEqual(environment.store.lastMessage, "Cleared all slots")
    }

    private func bind(
        window: WindowReference,
        to slotID: Int,
        in environment: TestEnvironment
    ) -> WindowReference {
        environment.windowService.captureResults = [.success(window)]
        environment.store.bindFocusedWindow(to: slotID)
        return window
    }
}

private final class TestEnvironment {
    let windowService = MockWindowService()
    let focusService = MockWindowFocusService()
    let lifecycleObserver = MockWindowLifecycleObserver()
    let store: WindowSlotStore

    init(slotIDs: [Int]) {
        store = WindowSlotStore(
            slotIDs: slotIDs,
            windowService: windowService,
            focusService: focusService,
            lifecycleObserver: lifecycleObserver
        )
    }
}

private final class MockWindowService: WindowServiceProtocol {
    var captureResults: [WindowCaptureResult] = []
    var validationResults: [ObjectIdentifier: WindowValidationResult] = [:]
    var focusedWindowIDs = Set<ObjectIdentifier>()
    var refreshedWindows: [WindowReference] = []

    func captureFocusedWindow() -> WindowCaptureResult {
        guard !captureResults.isEmpty else {
            return .failure("no capture result configured")
        }
        return captureResults.removeFirst()
    }

    func validate(_ window: WindowReference) -> WindowValidationResult {
        validationResults[ObjectIdentifier(window)] ?? .valid
    }

    func refreshFingerprint(for window: WindowReference) {
        refreshedWindows.append(window)
    }

    func focusedWindowMatches(_ window: WindowReference) -> Bool {
        focusedWindowIDs.contains(ObjectIdentifier(window))
    }
}

private final class MockWindowFocusService: WindowFocusServiceProtocol {
    var focusResult: WindowActionResult = .focused
    var completesFocusImmediately = true
    var focusedWindows: [WindowReference] = []
    private var pendingFocusCompletions: [(WindowActionResult) -> Void] = []

    var pendingFocusCompletionCount: Int {
        pendingFocusCompletions.count
    }

    func focus(_ window: WindowReference, completion: @escaping (WindowActionResult) -> Void) {
        focusedWindows.append(window)
        if completesFocusImmediately {
            completion(focusResult)
        } else {
            pendingFocusCompletions.append(completion)
        }
    }

    func completeNextFocus(with result: WindowActionResult? = nil) {
        completeFocus(at: 0, with: result)
    }

    func completeFocus(at index: Int, with result: WindowActionResult? = nil) {
        guard !pendingFocusCompletions.isEmpty else {
            XCTFail("No pending focus completion")
            return
        }
        guard pendingFocusCompletions.indices.contains(index) else {
            XCTFail("No pending focus completion at index \(index)")
            return
        }
        let completion = pendingFocusCompletions.remove(at: index)
        completion(result ?? focusResult)
    }
}

private final class MockWindowLifecycleObserver: WindowLifecycleObserving {
    var onWindowInvalidated: ((WindowReference, String) -> Void)?
    var watchResult: WindowLifecycleWatchResult = .observing
    var watchedSlots: [Int: WindowReference] = [:]
    var watchEvents: [Int] = []
    var unwatchedSlots: [Int] = []
    var didUnwatchAll = false

    func watch(_ window: WindowReference, slotID: Int) -> WindowLifecycleWatchResult {
        watchEvents.append(slotID)
        watchedSlots[slotID] = window
        return watchResult
    }

    func unwatchSlot(_ slotID: Int) {
        guard watchedSlots[slotID] != nil else {
            return
        }
        unwatchedSlots.append(slotID)
        watchedSlots[slotID] = nil
    }

    func unwatchAll() {
        watchedSlots.removeAll()
        didUnwatchAll = true
    }

    func invalidate(_ window: WindowReference, reason: String) {
        onWindowInvalidated?(window, reason)
    }
}

private func makeWindow(
    pid: pid_t = 10_000,
    appName: String = "Test App",
    bundleIdentifier: String = "dev.test.App",
    title: String = "Window",
    handleID: Int? = nil
) -> WindowReference {
    let handle = TestWindowElementHandle(id: handleID ?? Int(pid))
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
        handle: handle,
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

private final class TestWindowElementHandle: WindowElementHandle {
    let id: Int

    init(id: Int) {
        self.id = id
    }

    func isSameWindow(as other: WindowElementHandle) -> Bool {
        guard let other = other as? TestWindowElementHandle else {
            return false
        }
        return id == other.id
    }
}

private extension WindowSlotStore {
    func slot(_ id: Int) -> WindowSlot {
        guard let slot = slots.first(where: { $0.id == id }) else {
            XCTFail("Missing slot \(id)")
            return WindowSlot(id: id)
        }
        return slot
    }
}
