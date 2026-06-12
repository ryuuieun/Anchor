import Foundation

private let slotLogger = AnchorLog.slots

final class WindowSlotStore: ObservableObject {
    @Published private(set) var slots: [WindowSlot]
    @Published private(set) var lastMessage = "Ready"

    private let windowService: WindowServiceProtocol
    private let focusService: WindowFocusServiceProtocol
    private let lifecycleObserver: WindowLifecycleObserving
    private var activationGenerationsBySlotID: [Int: UInt64] = [:]
    private var nextActivationGeneration: UInt64 = 0

    init(
        slotIDs: [Int],
        windowService: WindowServiceProtocol,
        focusService: WindowFocusServiceProtocol,
        lifecycleObserver: WindowLifecycleObserving = WindowLifecycleObserver()
    ) {
        slots = slotIDs.map { WindowSlot(id: $0) }
        self.windowService = windowService
        self.focusService = focusService
        self.lifecycleObserver = lifecycleObserver
        self.lifecycleObserver.onWindowInvalidated = { [weak self] window, reason in
            self?.clearBindings(for: window, reason: reason)
        }
    }

    func bindFocusedWindow(to slotID: Int) {
        slotLogger.info("Bind requested for slot \(slotID)")
        guard slots.contains(where: { $0.id == slotID }) else {
            lastMessage = "Unknown slot \(slotID)"
            return
        }

        switch windowService.captureFocusedWindow() {
        case .success(let window):
            bindWindow(window, to: slotID)

        case .failure(let reason):
            lastMessage = "Could not bind slot \(slotID): \(reason)"
            slotLogger.error("Bind failed for slot \(slotID): \(reason, privacy: .public)")
        }
    }

    func bindWindow(_ window: WindowReference, to slotID: Int) {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else {
            lastMessage = "Unknown slot \(slotID)"
            return
        }

        for index in slots.indices {
            if slots[index].window?.isSameWindow(as: window) == true {
                invalidateActivation(for: slots[index].id)
                lifecycleObserver.unwatchSlot(slots[index].id)
                slots[index].window = nil
                slots[index].status = .empty
            }
        }

        invalidateActivation(for: slotID)
        lifecycleObserver.unwatchSlot(slotID)
        slots[index].window = window
        slots[index].status = .bound
        switch lifecycleObserver.watch(window, slotID: slotID) {
        case .observing:
            lastMessage = "Bound slot \(slotID) to \(window.summary)"
        case .appTerminationOnly(let reason):
            lastMessage = "Bound slot \(slotID) to \(window.summary) (close listener unavailable: \(reason))"
        }
        slotLogger.info("Bound slot \(slotID) to \(window.summary, privacy: .public) pid \(window.pid)")
    }

    func activate(slotID: Int) {
        slotLogger.info("Activate requested for slot \(slotID)")
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else {
            lastMessage = "Unknown slot \(slotID)"
            slotLogger.error("Activate failed for unknown slot \(slotID)")
            return
        }

        guard let window = slots[index].window else {
            lastMessage = "Slot \(slotID) is empty"
            slots[index].status = .empty
            slotLogger.error("Activate failed because slot \(slotID) is empty")
            return
        }

        let activationGeneration = startActivation(for: slotID)
        switch windowService.validate(window) {
        case .valid:
            break
        case .updatedFingerprint:
            rewatchWindow(window, slotID: slotID)
        case .temporarilyUnavailable(let reason):
            markTemporarilyUnavailable(at: index, reason: reason)
            slotLogger.error("Slot \(slotID) temporarily unavailable: \(reason, privacy: .public)")
            return
        case .accessibilityUnavailable(let reason):
            markAccessibilityUnavailable(at: index, reason: reason)
            slotLogger.error("Slot \(slotID) accessibility unavailable: \(reason, privacy: .public)")
            return
        case .missing(let reason), .ambiguous(let reason):
            clearBinding(at: index, reason: reason)
            slotLogger.error("Cleared slot \(slotID) because bound window is unavailable: \(reason, privacy: .public)")
            return
        }

        if windowService.focusedWindowMatches(window) {
            slotLogger.info("Slot \(slotID) already focused; no window action needed")
            slots[index].status = .bound
            lastMessage = "Slot \(slotID): \(WindowActionResult.focused.statusMessage)"
            slotLogger.info("Slot \(slotID) result: \(WindowActionResult.focused.statusMessage, privacy: .public)")
        } else {
            slots[index].status = .switching
            lastMessage = "Slot \(slotID): switching to \(window.summary)"
            slotLogger.info("Slot \(slotID) switching to \(window.summary, privacy: .public)")
            focusService.focus(window) { [weak self] result in
                guard let self else {
                    return
                }
                apply(result, to: window, slotID: slotID, activationGeneration: activationGeneration)
            }
        }
    }

    private func apply(
        _ result: WindowActionResult,
        to window: WindowReference,
        slotID: Int,
        activationGeneration: UInt64
    ) {
        guard activationGenerationsBySlotID[slotID] == activationGeneration else {
            slotLogger.debug("Ignoring stale activation result for slot \(slotID)")
            return
        }

        guard let index = slots.firstIndex(where: { slot in
            slot.id == slotID && slot.window?.isSameWindow(as: window) == true
        }) else {
            return
        }

        switch result {
        case .focused:
            windowService.refreshFingerprint(for: window)
            slots[index].status = .bound
        case .unsupported(let reason), .failed(let reason), .focusVerificationFailed(let reason):
            slots[index].status = .actionFailed(reason)
        }
        lastMessage = "Slot \(slotID): \(result.statusMessage)"
        slotLogger.info("Slot \(slotID) result: \(result.statusMessage, privacy: .public)")
    }

    func clear(slotID: Int) {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else {
            slotLogger.error("Clear requested for unknown slot \(slotID)")
            return
        }
        slotLogger.info("Clearing slot \(slotID)")
        invalidateActivation(for: slotID)
        lifecycleObserver.unwatchSlot(slotID)
        slots[index].window = nil
        slots[index].status = .empty
        lastMessage = "Cleared slot \(slotID)"
    }

    func clearAll() {
        slotLogger.info("Clearing all slots")
        activationGenerationsBySlotID.removeAll()
        lifecycleObserver.unwatchAll()
        for index in slots.indices {
            slots[index].window = nil
            slots[index].status = .empty
        }
        lastMessage = "Cleared all slots"
    }

    func refreshStatuses() {
        slotLogger.debug("Refreshing slot statuses")
        applyStatusRefreshResults(validateStatusRefreshRequests(makeStatusRefreshRequests()))
    }

    func makeStatusRefreshRequests() -> [WindowStatusRefreshRequest] {
        slots.compactMap { slot in
            guard let window = slot.window else {
                return nil
            }
            return WindowStatusRefreshRequest(slotID: slot.id, window: window)
        }
    }

    func validateStatusRefreshRequests(_ requests: [WindowStatusRefreshRequest]) -> [WindowStatusRefreshResult] {
        requests.map { request in
            slotLogger.debug("Refreshing slot \(request.slotID) status for \(request.window.summary, privacy: .public)")
            return WindowStatusRefreshResult(
                slotID: request.slotID,
                window: request.window,
                validationResult: windowService.validate(request.window)
            )
        }
    }

    func applyStatusRefreshResults(_ results: [WindowStatusRefreshResult]) {
        for result in results {
            guard let index = slots.firstIndex(where: { slot in
                slot.id == result.slotID && slot.window === result.window
            }) else {
                slotLogger.debug("Ignoring stale status refresh result for slot \(result.slotID)")
                continue
            }

            apply(result.validationResult, toBoundSlotAt: index, window: result.window)
        }
    }

    private func apply(
        _ validationResult: WindowValidationResult,
        toBoundSlotAt index: Int,
        window: WindowReference
    ) {
        switch validationResult {
        case .valid:
            if slots[index].status.canRecoverToBoundOnValidationSuccess {
                slots[index].status = .bound
            }
            slotLogger.debug("Slot \(self.slots[index].id) validation valid")
        case .updatedFingerprint:
            rewatchWindow(window, slotID: slots[index].id)
            if slots[index].status.canRecoverToBoundOnValidationSuccess {
                slots[index].status = .bound
            }
            slotLogger.info("Slot \(self.slots[index].id) validation updated fingerprint")
        case .temporarilyUnavailable(let reason):
            markTemporarilyUnavailable(at: index, reason: reason)
        case .accessibilityUnavailable(let reason):
            markAccessibilityUnavailable(at: index, reason: reason)
        case .missing(let reason), .ambiguous(let reason):
            clearBinding(at: index, reason: reason)
        }
    }

    private func markTemporarilyUnavailable(at index: Int, reason: String) {
        let slotID = slots[index].id
        slots[index].status = .unavailable(reason)
        lastMessage = "Slot \(slotID) temporarily unavailable: \(reason)"
    }

    private func markAccessibilityUnavailable(at index: Int, reason: String) {
        let slotID = slots[index].id
        slots[index].status = .accessibilityUnavailable(reason)
        lastMessage = "Slot \(slotID) accessibility unavailable: \(reason)"
    }

    private func clearBinding(at index: Int, reason: String) {
        let slotID = slots[index].id
        slotLogger.info("Clearing slot \(slotID) because \(reason, privacy: .public)")
        invalidateActivation(for: slotID)
        lifecycleObserver.unwatchSlot(slotID)
        slots[index].window = nil
        slots[index].status = .empty
        lastMessage = "Cleared slot \(slotID): \(reason)"
    }

    private func rewatchWindow(_ window: WindowReference, slotID: Int) {
        lifecycleObserver.unwatchSlot(slotID)
        switch lifecycleObserver.watch(window, slotID: slotID) {
        case .observing:
            slotLogger.debug("Rewatched lifecycle for slot \(slotID)")
            break
        case .appTerminationOnly(let reason):
            lastMessage = "Slot \(slotID): close listener unavailable after window refresh: \(reason)"
            slotLogger.error("Close listener unavailable after window refresh for slot \(slotID): \(reason, privacy: .public)")
        }
    }

    private func clearBindings(for window: WindowReference, reason: String) {
        var clearedSlotIDs: [Int] = []
        for index in slots.indices {
            guard slots[index].window?.isSameWindow(as: window) == true else {
                continue
            }
            let slotID = slots[index].id
            invalidateActivation(for: slotID)
            lifecycleObserver.unwatchSlot(slotID)
            slots[index].window = nil
            slots[index].status = .empty
            clearedSlotIDs.append(slotID)
        }

        guard !clearedSlotIDs.isEmpty else {
            return
        }

        let slotList = clearedSlotIDs.map(String.init).joined(separator: ", ")
        lastMessage = "Cleared slot \(slotList): \(reason)"
        slotLogger.info("Cleared slot \(slotList, privacy: .public) after lifecycle event: \(reason, privacy: .public)")
    }

    private func startActivation(for slotID: Int) -> UInt64 {
        if nextActivationGeneration == .max {
            nextActivationGeneration = 0
            activationGenerationsBySlotID.removeAll()
        }
        nextActivationGeneration += 1
        activationGenerationsBySlotID[slotID] = nextActivationGeneration
        return nextActivationGeneration
    }

    private func invalidateActivation(for slotID: Int) {
        activationGenerationsBySlotID[slotID] = nil
    }
}

struct WindowStatusRefreshRequest {
    let slotID: Int
    let window: WindowReference
}

struct WindowStatusRefreshResult {
    let slotID: Int
    let window: WindowReference
    let validationResult: WindowValidationResult
}

private extension WindowSlotStatus {
    var canRecoverToBoundOnValidationSuccess: Bool {
        switch self {
        case .unavailable, .accessibilityUnavailable:
            return true
        case .empty, .bound, .switching, .actionFailed:
            return false
        }
    }
}
