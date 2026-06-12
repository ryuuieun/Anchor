import AppKit
import ApplicationServices
import Foundation
import os

private let axLogger = AnchorLog.ax

final class AXWindowService: WindowServiceProtocol {
    private struct ApplicationCandidate {
        let element: AXUIElement
        let pid: pid_t
        let source: String
    }

    private enum WindowElementLookup {
        case success(AXUIElement)
        case failure(String)
    }

    private struct CandidateWindow {
        let handle: AXWindowHandle
        let title: String
        let subrole: String?
        let identifier: String?
        let fingerprint: WindowFingerprint
    }

    private struct CGWindowSnapshot {
        let id: CGWindowID
        let bounds: CGRect
        let layer: Int
        let title: String?
    }

    private enum ReplacementLookup {
        case found(CandidateWindow)
        case ambiguous(String)
        case missing
    }

    private enum BoundElementLookup {
        case readable(CandidateWindow)
        case temporarilyUnavailable(String)
        case accessibilityUnavailable(String)
        case stale
    }

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var lastExternalApplicationPID: pid_t?
    private var activationObserver: NSObjectProtocol?

    init() {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier != ownPID {
            lastExternalApplicationPID = frontmostApplication.processIdentifier
        }
        axLogger.info("AXWindowService initialized; ownPID=\(self.ownPID), lastExternalPID=\(self.lastExternalApplicationPID ?? 0)")

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != self.ownPID else {
                return
            }
            self.lastExternalApplicationPID = application.processIdentifier
            axLogger.debug("Remembered activated external app pid=\(application.processIdentifier), name=\(application.localizedName ?? "unknown", privacy: .public)")
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        axLogger.info("AXWindowService deinitialized")
    }

    func captureFocusedWindow() -> WindowCaptureResult {
        axLogger.info("Capturing focused window")
        rememberCurrentExternalFocus()
        switch currentWindowElement() {
        case .success(let windowElement):
            let result = makeWindowReference(from: windowElement)
            switch result {
            case .success(let window):
                axLogger.info("Captured focused window \(window.summary, privacy: .public) pid \(window.pid)")
            case .failure(let reason):
                axLogger.error("Failed to make focused window reference: \(reason, privacy: .public)")
            }
            return result
        case .failure(let reason):
            axLogger.error("Focused window capture failed: \(reason, privacy: .public)")
            return .failure(reason)
        }
    }

    func rememberCurrentExternalFocus() {
        axLogger.debug("Refreshing last external focus candidate")
        for candidate in applicationCandidates() {
            switch focusedOrMainWindow(from: candidate) {
            case .success(let windowElement):
                if case .success(let windowReference) = makeWindowReference(from: windowElement) {
                    lastExternalApplicationPID = windowReference.pid
                    axLogger.debug("Last external focus updated to pid=\(windowReference.pid), window=\(windowReference.summary, privacy: .public)")
                }
                return
            case .failure:
                continue
            }
        }
        axLogger.debug("No external focus candidate available")
    }

    private func makeWindowReference(from windowElement: AXUIElement) -> WindowCaptureResult {
        let windowElement = AXElementSafety.applyMessagingTimeout(to: windowElement)
        var pid: pid_t = 0
        let pidError = AXUIElementGetPid(windowElement, &pid)
        guard pidError == .success, pid > 0 else {
            return .failure("Could not read focused window process id (\(pidError.readableDescription))")
        }

        if pid == ownPID {
            return .failure("Anchor is focused; focus another app window before binding")
        }

        let role = AXAttributeReader.stringAttribute(kAXRoleAttribute, from: windowElement) ?? ""
        guard role == kAXWindowRole as String else {
            return .failure("Focused accessibility element is not a macOS top-level window")
        }

        let app = NSRunningApplication(processIdentifier: pid)
        let appName = app?.localizedName ?? "PID \(pid)"
        let title = AXAttributeReader.stringAttribute(kAXTitleAttribute, from: windowElement) ?? ""
        let subrole = AXAttributeReader.stringAttribute(kAXSubroleAttribute, from: windowElement)
        let identifier = AXAttributeReader.stringAttribute(kAXIdentifierAttribute, from: windowElement)
        let fingerprint = makeFingerprint(
            from: windowElement,
            pid: pid,
            bundleIdentifier: app?.bundleIdentifier,
            title: title,
            role: role,
            subrole: subrole,
            identifier: identifier
        )

        return .success(WindowReference(
            handle: AXWindowHandle(windowElement),
            pid: pid,
            appName: appName,
            bundleIdentifier: app?.bundleIdentifier,
            bundleURL: app?.bundleURL,
            title: title,
            role: role,
            subrole: subrole,
            identifier: identifier,
            fingerprint: fingerprint
        ))
    }

    func validate(_ window: WindowReference) -> WindowValidationResult {
        axLogger.debug("Validating bound window \(window.summary, privacy: .public) pid \(window.pid)")
        guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else {
            axLogger.info("Validation missing for \(window.summary, privacy: .public): app exited")
            return .missing("app exited")
        }

        switch boundElementLookup(for: window) {
        case .readable(let current):
            let changed = window.updateSnapshot(
                handle: current.handle,
                title: current.title,
                subrole: current.subrole,
                identifier: current.identifier,
                fingerprint: current.fingerprint
            )
            axLogger.debug("Validation used existing AX handle for \(window.summary, privacy: .public); changed=\(changed)")
            return changed ? .updatedFingerprint : .valid
        case .temporarilyUnavailable(let reason):
            axLogger.info("Validation temporarily unavailable for \(window.summary, privacy: .public): \(reason, privacy: .public)")
            return .temporarilyUnavailable(reason)
        case .accessibilityUnavailable(let reason):
            axLogger.error("Validation accessibility unavailable for \(window.summary, privacy: .public): \(reason, privacy: .public)")
            return .accessibilityUnavailable(reason)
        case .stale:
            axLogger.debug("Existing AX handle is stale for \(window.summary, privacy: .public); scanning app window list")
            break
        }

        let appElement = AXElementSafety.applicationElement(pid: window.pid)
        let windowsResult = AXAttributeReader.elementsAttribute(kAXWindowsAttribute, from: appElement)

        guard windowsResult.error == .success, let windows = windowsResult.elements else {
            if windowsResult.error.isAccessibilityUnavailable {
                axLogger.error("Window list accessibility unavailable for \(window.summary, privacy: .public): \(windowsResult.error.readableDescription, privacy: .public)")
                return .accessibilityUnavailable("Accessibility permission is required (\(windowsResult.error.readableDescription))")
            }
            if windowsResult.error.isTemporaryUnavailable {
                axLogger.info("Window list temporarily unavailable for \(window.summary, privacy: .public): \(windowsResult.error.readableDescription, privacy: .public)")
                return .temporarilyUnavailable("window list unavailable: \(windowsResult.error.readableDescription)")
            }
            axLogger.info("Window list missing for \(window.summary, privacy: .public): \(windowsResult.error.readableDescription, privacy: .public)")
            return .missing("window list unavailable")
        }
        axLogger.debug("Scanning \(windows.count) AX windows for \(window.summary, privacy: .public)")

        if let current = windows.compactMap({ candidateWindow(from: $0, reference: window) }).first(where: {
            $0.handle.isSameWindow(as: window.handle)
        }) {
            let changed = window.updateSnapshot(
                handle: current.handle,
                title: current.title,
                subrole: current.subrole,
                identifier: current.identifier,
                fingerprint: current.fingerprint
            )
            axLogger.debug("Validation found same AX handle in window list for \(window.summary, privacy: .public); changed=\(changed)")
            return changed ? .updatedFingerprint : .valid
        }

        switch confidentReplacement(for: window, in: windows) {
        case .found(let replacement):
            window.updateSnapshot(
                handle: replacement.handle,
                title: replacement.title,
                subrole: replacement.subrole,
                identifier: replacement.identifier,
                fingerprint: replacement.fingerprint
            )
            axLogger.info("Validation found high-confidence replacement for \(window.summary, privacy: .public)")
            return .updatedFingerprint
        case .ambiguous(let reason):
            axLogger.info("Validation ambiguous for \(window.summary, privacy: .public): \(reason, privacy: .public)")
            return .ambiguous(reason)
        case .missing:
            axLogger.info("Validation missing for \(window.summary, privacy: .public): window closed")
            return .missing("window closed")
        }
    }

    func refreshFingerprint(for window: WindowReference) {
        guard case .readable(let current) = boundElementLookup(for: window) else {
            axLogger.debug("Skipped fingerprint refresh because AX handle is not readable for \(window.summary, privacy: .public)")
            return
        }

        window.updateSnapshot(
            handle: current.handle,
            title: current.title,
            subrole: current.subrole,
            identifier: current.identifier,
            fingerprint: current.fingerprint
        )
        axLogger.debug("Refreshed fingerprint for \(window.summary, privacy: .public)")
    }

    func focusedWindowMatches(_ window: WindowReference) -> Bool {
        let axFocusedApplicationPID = focusedApplicationCandidate()?.pid
        let workspaceFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard FocusedWindowMatchPolicy.targetApplicationCanOwnFocusedWindow(
            targetPID: window.pid,
            ownPID: ownPID,
            axFocusedApplicationPID: axFocusedApplicationPID,
            workspaceFrontmostPID: workspaceFrontmostPID
        ) else {
            axLogger.debug(
                "Focused window match rejected by app ownership policy for targetPID=\(window.pid), axFocusedPID=\(axFocusedApplicationPID ?? 0), workspacePID=\(workspaceFrontmostPID ?? 0)"
            )
            return false
        }

        let appElement = AXElementSafety.applicationElement(pid: window.pid)
        let focusedWindowResult = AXAttributeReader.elementAttribute(
            kAXFocusedWindowAttribute,
            from: appElement
        )
        if let focusedWindow = focusedWindowResult.element,
           windowElement(focusedWindow, matches: window) {
            axLogger.debug("Focused window matches target \(window.summary, privacy: .public)")
            return true
        }

        let mainWindowResult = AXAttributeReader.elementAttribute(
            kAXMainWindowAttribute,
            from: appElement
        )
        guard let mainWindow = mainWindowResult.element else {
            axLogger.debug("Focused window does not match and main window unavailable for \(window.summary, privacy: .public)")
            return false
        }
        let matches = windowElement(mainWindow, matches: window)
        axLogger.debug("Main window match for \(window.summary, privacy: .public): \(matches)")
        return matches
    }

    private func currentWindowElement() -> WindowElementLookup {
        var failures: [String] = []
        let candidates = applicationCandidates()
        axLogger.debug("Looking for focused/current window across \(candidates.count) application candidates")

        for candidate in candidates {
            switch focusedOrMainWindow(from: candidate) {
            case .success(let windowElement):
                axLogger.debug("Found focused/current window from \(candidate.source, privacy: .public) pid \(candidate.pid)")
                return .success(windowElement)
            case .failure(let reason):
                failures.append(reason)
            }
        }

        if failures.isEmpty {
            return .failure("No focused application is available")
        }
        return .failure("No focused top-level window is available (\(failures.joined(separator: "; ")))")
    }

    private func applicationCandidates() -> [ApplicationCandidate] {
        var candidates: [ApplicationCandidate] = []
        var seenPIDs = Set<pid_t>()

        func append(pid: pid_t, element: AXUIElement, source: String) {
            guard pid > 0, pid != ownPID, !seenPIDs.contains(pid) else {
                return
            }
            seenPIDs.insert(pid)
            candidates.append(ApplicationCandidate(element: element, pid: pid, source: source))
        }

        if let candidate = focusedApplicationCandidate() {
            append(pid: candidate.pid, element: candidate.element, source: candidate.source)
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            append(
                pid: frontmostApplication.processIdentifier,
                element: AXElementSafety.applicationElement(pid: frontmostApplication.processIdentifier),
                source: "frontmost application"
            )
        }

        if let lastExternalApplicationPID,
           NSRunningApplication(processIdentifier: lastExternalApplicationPID) != nil {
            append(
                pid: lastExternalApplicationPID,
                element: AXElementSafety.applicationElement(pid: lastExternalApplicationPID),
                source: "last active external application"
            )
        }

        return candidates
    }

    private func focusedApplicationCandidate() -> ApplicationCandidate? {
        let systemElement = AXElementSafety.systemWideElement()
        let focusedApplicationResult = AXAttributeReader.elementAttribute(kAXFocusedApplicationAttribute, from: systemElement)
        guard focusedApplicationResult.error == .success,
              let applicationElement = focusedApplicationResult.element else {
            return nil
        }

        var pid: pid_t = 0
        let pidError = AXUIElementGetPid(applicationElement, &pid)
        guard pidError == .success, pid > 0 else {
            return nil
        }

        return ApplicationCandidate(
            element: applicationElement,
            pid: pid,
            source: "focused application"
        )
    }

    private func focusedOrMainWindow(from candidate: ApplicationCandidate) -> WindowElementLookup {
        let focusedResult = AXAttributeReader.elementAttribute(kAXFocusedWindowAttribute, from: candidate.element)
        if let element = focusedResult.element {
            return .success(element)
        }

        let mainResult = AXAttributeReader.elementAttribute(kAXMainWindowAttribute, from: candidate.element)
        if let element = mainResult.element {
            return .success(element)
        }

        return .failure(
            "\(candidate.source) PID \(candidate.pid): focused window \(focusedResult.error.readableDescription), main window \(mainResult.error.readableDescription)"
        )
    }

    private func boundElementLookup(for window: WindowReference) -> BoundElementLookup {
        guard let element = window.axElement else {
            return .stale
        }

        AXElementSafety.applyMessagingTimeout(to: element)
        let roleResult = AXAttributeReader.stringAttributeResult(kAXRoleAttribute, from: element)
        guard roleResult.error == .success, let role = roleResult.value else {
            if roleResult.error.isAccessibilityUnavailable {
                return .accessibilityUnavailable("Accessibility permission is required (\(roleResult.error.readableDescription))")
            }
            if roleResult.error.isTemporaryUnavailable {
                return .temporarilyUnavailable("window temporarily unavailable: \(roleResult.error.readableDescription)")
            }
            return .stale
        }

        guard role == window.role else {
            return .stale
        }

        let title = AXAttributeReader.stringAttributeIfAvailable(kAXTitleAttribute, from: element) ?? window.title
        let subrole = AXAttributeReader.stringAttributeIfAvailable(kAXSubroleAttribute, from: element)
        let identifier = AXAttributeReader.stringAttributeIfAvailable(kAXIdentifierAttribute, from: element)
        let fingerprint = makeFingerprint(
            from: element,
            pid: window.pid,
            bundleIdentifier: window.bundleIdentifier,
            title: title,
            role: role,
            subrole: subrole,
            identifier: identifier
        )

        return .readable(CandidateWindow(
            handle: AXWindowHandle(element),
            title: title,
            subrole: subrole,
            identifier: identifier,
            fingerprint: fingerprint
        ))
    }

    private func confidentReplacement(for window: WindowReference, in windows: [AXUIElement]) -> ReplacementLookup {
        let candidates = windows.compactMap { candidateWindow(from: $0, reference: window) }
        axLogger.debug("Matching fingerprint for \(window.summary, privacy: .public): candidates=\(candidates.count)")
        switch WindowFingerprintMatcher.match(
            original: window.fingerprint,
            candidates: candidates.map(\.fingerprint)
        ) {
        case .match(let index):
            axLogger.debug("Fingerprint match succeeded for \(window.summary, privacy: .public) at candidate index \(index)")
            return .found(candidates[index])
        case .missing:
            axLogger.debug("Fingerprint match missing for \(window.summary, privacy: .public)")
            return .missing
        case .ambiguous(let reason):
            axLogger.debug("Fingerprint match ambiguous for \(window.summary, privacy: .public): \(reason, privacy: .public)")
            return .ambiguous(reason)
        }
    }

    private func candidateWindow(from element: AXUIElement, reference window: WindowReference) -> CandidateWindow? {
        let element = AXElementSafety.applyMessagingTimeout(to: element)
        let role = AXAttributeReader.stringAttribute(kAXRoleAttribute, from: element) ?? ""
        guard role == window.role else {
            return nil
        }

        let title = AXAttributeReader.stringAttribute(kAXTitleAttribute, from: element) ?? ""
        let subrole = AXAttributeReader.stringAttribute(kAXSubroleAttribute, from: element)
        let identifier = AXAttributeReader.stringAttribute(kAXIdentifierAttribute, from: element)
        let fingerprint = makeFingerprint(
            from: element,
            pid: window.pid,
            bundleIdentifier: window.bundleIdentifier,
            title: title,
            role: role,
            subrole: subrole,
            identifier: identifier
        )

        return CandidateWindow(
            handle: AXWindowHandle(element),
            title: title,
            subrole: subrole,
            identifier: identifier,
            fingerprint: fingerprint
        )
    }

    private func windowElement(_ element: AXUIElement, matches window: WindowReference) -> Bool {
        let handle = AXWindowHandle(element)
        if handle.isSameWindow(as: window.handle) {
            return true
        }

        guard let candidate = candidateWindow(from: element, reference: window) else {
            return false
        }

        switch WindowFingerprintMatcher.match(original: window.fingerprint, candidates: [candidate.fingerprint]) {
        case .match:
            return true
        case .missing, .ambiguous:
            return false
        }
    }

    private func makeFingerprint(
        from element: AXUIElement,
        pid: pid_t,
        bundleIdentifier: String?,
        title: String,
        role: String,
        subrole: String?,
        identifier: String?
    ) -> WindowFingerprint {
        let position = AXAttributeReader.pointAttribute(kAXPositionAttribute, from: element)
        let size = AXAttributeReader.sizeAttribute(kAXSizeAttribute, from: element)
        let cgWindow = matchingCGWindow(pid: pid, title: title, position: position, size: size)

        return WindowFingerprint(
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            title: title,
            role: role,
            subrole: subrole,
            identifier: identifier,
            position: position,
            size: size,
            cgWindowID: cgWindow?.id,
            cgBounds: cgWindow?.bounds,
            cgLayer: cgWindow?.layer
        )
    }

    private func matchingCGWindow(
        pid: pid_t,
        title: String,
        position: CGPoint?,
        size: CGSize?
    ) -> CGWindowSnapshot? {
        guard let position, let size else {
            return nil
        }

        let axBounds = CGRect(origin: position, size: size)
        let tolerance: CGFloat = 8
        let geometryMatches = cgWindows(for: pid).filter {
            $0.bounds.matches(axBounds, tolerance: tolerance)
        }
        guard !geometryMatches.isEmpty else {
            return nil
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleMatches = geometryMatches.filter { snapshot in
            guard !trimmedTitle.isEmpty,
                  let snapshotTitle = snapshot.title?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                  !snapshotTitle.isEmpty else {
                return false
            }
            return snapshotTitle == trimmedTitle
        }

        let preferredMatches = titleMatches.isEmpty ? geometryMatches : titleMatches
        let normalLayerMatches = preferredMatches.filter { $0.layer == 0 }
        let finalMatches = normalLayerMatches.isEmpty ? preferredMatches : normalLayerMatches
        return finalMatches.count == 1 ? finalMatches[0] : nil
    }

    private func cgWindows(for pid: pid_t) -> [CGWindowSnapshot] {
        guard let windowInfo = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfo.compactMap { info in
            guard let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == pid,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue else {
                return nil
            }

            return CGWindowSnapshot(
                id: CGWindowID(number),
                bounds: bounds,
                layer: layer,
                title: info[kCGWindowName as String] as? String
            )
        }
    }

}

private extension CGRect {
    func matches(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance
            && abs(size.height - other.size.height) <= tolerance
    }
}

extension AXError {
    var isAccessibilityUnavailable: Bool {
        switch self {
        case .apiDisabled:
            return true
        default:
            return false
        }
    }

    var isTemporaryUnavailable: Bool {
        switch self {
        case .cannotComplete:
            return true
        default:
            return false
        }
    }

    var readableDescription: String {
        switch self {
        case .success:
            return "success"
        case .failure:
            return "failure"
        case .illegalArgument:
            return "illegal argument"
        case .invalidUIElement:
            return "invalid UI element"
        case .invalidUIElementObserver:
            return "invalid UI element observer"
        case .cannotComplete:
            return "cannot complete"
        case .attributeUnsupported:
            return "attribute unsupported"
        case .actionUnsupported:
            return "action unsupported"
        case .notificationUnsupported:
            return "notification unsupported"
        case .notImplemented:
            return "not implemented"
        case .notificationAlreadyRegistered:
            return "notification already registered"
        case .notificationNotRegistered:
            return "notification not registered"
        case .apiDisabled:
            return "accessibility API disabled"
        case .noValue:
            return "no value"
        case .parameterizedAttributeUnsupported:
            return "parameterized attribute unsupported"
        case .notEnoughPrecision:
            return "not enough precision"
        @unknown default:
            return "unknown AX error \(rawValue)"
        }
    }
}
