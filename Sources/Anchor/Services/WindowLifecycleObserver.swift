import AppKit
import ApplicationServices
import Foundation

private let lifecycleLogger = AnchorLog.lifecycle

enum WindowLifecycleWatchResult {
    case observing
    case appTerminationOnly(String)
}

final class WindowLifecycleObserver: WindowLifecycleObserving {
    var onWindowInvalidated: ((WindowReference, String) -> Void)?

    private enum SetupResult<Value> {
        case success(Value)
        case failure(String)
    }

    private struct Registration {
        let slotID: Int
        let window: WindowReference
        let observesWindowDestroyed: Bool
    }

    private final class ApplicationObserver {
        let pid: pid_t
        let observer: AXObserver
        let runLoopSource: CFRunLoopSource
        var slotIDs = Set<Int>()

        init(pid: pid_t, observer: AXObserver, runLoopSource: CFRunLoopSource) {
            self.pid = pid
            self.observer = observer
            self.runLoopSource = runLoopSource
        }
    }

    private var registrationsBySlotID: [Int: Registration] = [:]
    private var observersByPID: [pid_t: ApplicationObserver] = [:]
    private var appTerminationObserver: NSObjectProtocol?

    init() {
        appTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.handleApplicationTerminated(pid: application.processIdentifier)
        }
    }

    deinit {
        unwatchAll()
        if let appTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appTerminationObserver)
        }
    }

    func watch(_ window: WindowReference, slotID: Int) -> WindowLifecycleWatchResult {
        unwatchSlot(slotID)

        switch registerWindowDestroyedNotification(for: window, slotID: slotID) {
        case .success:
            registrationsBySlotID[slotID] = Registration(
                slotID: slotID,
                window: window,
                observesWindowDestroyed: true
            )
            lifecycleLogger.info("Observing destroyed notification for slot \(slotID) pid \(window.pid)")
            return .observing

        case .failure(let reason):
            registrationsBySlotID[slotID] = Registration(
                slotID: slotID,
                window: window,
                observesWindowDestroyed: false
            )
            lifecycleLogger.error("Window destroyed notification unavailable for slot \(slotID): \(reason, privacy: .public)")
            return .appTerminationOnly(reason)
        }
    }

    func unwatchSlot(_ slotID: Int) {
        guard let registration = registrationsBySlotID.removeValue(forKey: slotID) else {
            return
        }
        lifecycleLogger.debug("Unwatching slot \(slotID) pid \(registration.window.pid)")

        guard registration.observesWindowDestroyed,
              let appObserver = observersByPID[registration.window.pid],
              let element = registration.window.axElement else {
            return
        }

        AXElementSafety.applyMessagingTimeout(to: element)
        AXObserverRemoveNotification(
            appObserver.observer,
            element,
            kAXUIElementDestroyedNotification as CFString
        )

        appObserver.slotIDs.remove(slotID)
        removeApplicationObserverIfUnused(for: registration.window.pid)
    }

    func unwatchAll() {
        lifecycleLogger.info("Unwatching all lifecycle registrations count=\(self.registrationsBySlotID.count)")
        for slotID in Array(registrationsBySlotID.keys) {
            unwatchSlot(slotID)
        }
        registrationsBySlotID.removeAll()

        for appObserver in observersByPID.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), appObserver.runLoopSource, .commonModes)
        }
        observersByPID.removeAll()
    }

    private func registerWindowDestroyedNotification(
        for window: WindowReference,
        slotID: Int
    ) -> SetupResult<Void> {
        let observerResult = applicationObserver(for: window.pid)
        guard case .success(let appObserver) = observerResult else {
            if case .failure(let reason) = observerResult {
                return .failure(reason)
            }
            return .failure("unknown observer creation failure")
        }

        guard let element = window.axElement else {
            removeApplicationObserverIfUnused(for: window.pid)
            return .failure("bound window handle is not an Accessibility window")
        }
        let windowElement = AXElementSafety.applyMessagingTimeout(to: element)
        let addError = AXObserverAddNotification(
            appObserver.observer,
            windowElement,
            kAXUIElementDestroyedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )

        guard addError == .success || addError == .notificationAlreadyRegistered else {
            removeApplicationObserverIfUnused(for: window.pid)
            return .failure("AXUIElementDestroyed \(addError.readableDescription)")
        }

        appObserver.slotIDs.insert(slotID)
        return .success(())
    }

    private func applicationObserver(for pid: pid_t) -> SetupResult<ApplicationObserver> {
        if let appObserver = observersByPID[pid] {
            return .success(appObserver)
        }

        var observer: AXObserver?
        let createError = AXObserverCreate(pid, Self.observerCallback, &observer)
        guard createError == .success, let observer else {
            return .failure("AXObserverCreate \(createError.readableDescription)")
        }

        let runLoopSource = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

        let appObserver = ApplicationObserver(
            pid: pid,
            observer: observer,
            runLoopSource: runLoopSource
        )
        observersByPID[pid] = appObserver
        lifecycleLogger.info("Created AXObserver for pid \(pid)")
        return .success(appObserver)
    }

    private func removeApplicationObserverIfUnused(for pid: pid_t) {
        guard let appObserver = observersByPID[pid], appObserver.slotIDs.isEmpty else {
            return
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), appObserver.runLoopSource, .commonModes)
        observersByPID[pid] = nil
        lifecycleLogger.debug("Removed unused AXObserver for pid \(pid)")
    }

    private func handleWindowDestroyed(element: AXUIElement) {
        let destroyedWindows = registrationsBySlotID.values
            .filter { registration in
                guard registration.observesWindowDestroyed,
                      let registeredElement = registration.window.axElement else {
                    return false
                }
                return CFEqual(registeredElement, element)
            }
            .map(\.window)

        for window in destroyedWindows {
            lifecycleLogger.info("Window destroyed notification matched \(window.summary, privacy: .public) pid \(window.pid)")
            onWindowInvalidated?(window, "window closed")
        }
    }

    private func handleApplicationTerminated(pid: pid_t) {
        let exitedWindows = registrationsBySlotID.values
            .filter { $0.window.pid == pid }
            .map(\.window)

        for window in exitedWindows {
            lifecycleLogger.info("Application terminated for bound window \(window.summary, privacy: .public) pid \(pid)")
            onWindowInvalidated?(window, "app exited")
        }
    }

    private static let observerCallback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else {
            return
        }

        let observer = Unmanaged<WindowLifecycleObserver>
            .fromOpaque(refcon)
            .takeUnretainedValue()

        guard notification as String == kAXUIElementDestroyedNotification as String else {
            return
        }

        DispatchQueue.main.async {
            observer.handleWindowDestroyed(element: element)
        }
    }
}
