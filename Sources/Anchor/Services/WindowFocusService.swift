import AppKit
import ApplicationServices
import Foundation

private let focusLogger = AnchorLog.focus

final class WindowFocusService: WindowFocusServiceProtocol {
    private let focusVerifier: WindowFocusVerifier

    init(focusVerifier: WindowFocusVerifier = WindowFocusVerifier(reader: AXWindowFocusVerificationReader())) {
        self.focusVerifier = focusVerifier
    }

    func focus(_ window: WindowReference, completion: @escaping (WindowActionResult) -> Void) {
        guard let element = window.axElement else {
            focusLogger.error("Focus failed for \(window.summary, privacy: .public): bound window handle is not an Accessibility window")
            completion(.failed("Bound window handle is not an Accessibility window"))
            return
        }
        AXElementSafety.applyMessagingTimeout(to: element)
        focusLogger.info("Focus requested for \(window.summary, privacy: .public) pid \(window.pid)")
        guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else {
            focusLogger.error("Focus failed for \(window.summary, privacy: .public): app is no longer running")
            completion(.failed("App is no longer running"))
            return
        }

        if app.isHidden {
            focusLogger.info("Target app is hidden; unhide requested for pid \(window.pid)")
            _ = app.unhide()
        }

        let restoreResult = restoreIfMinimized(window)
        switch restoreResult {
        case .failed, .unsupported, .focusVerificationFailed:
            focusLogger.error("Restore before focus failed for \(window.summary, privacy: .public): \(restoreResult.statusMessage, privacy: .public)")
            completion(restoreResult)
            return
        case .focused:
            break
        }

        var diagnostics: [String] = []
        diagnostics.append(setTargetAsMain(window))
        activateApplication(for: window, runningApplication: app) { [weak self] activationDiagnostic in
            guard let self else {
                completion(.failed("Focus service was released"))
                return
            }

            var nextDiagnostics = diagnostics
            if let activationDiagnostic {
                nextDiagnostics.append(activationDiagnostic)
                focusLogger.error("\(activationDiagnostic, privacy: .public)")
            }
            self.performSingleFocusAttempt(window, diagnostics: nextDiagnostics, completion: completion)
        }
    }

    private func activateApplication(
        for window: WindowReference,
        runningApplication app: NSRunningApplication,
        completion: @escaping (String?) -> Void
    ) {
        if let bundleURL = window.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            configuration.promptsUserIfNeeded = false
            configuration.createsNewApplicationInstance = false
            configuration.allowsRunningApplicationSubstitution = true

            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { openedApp, error in
                DispatchQueue.main.async {
                    let targetApp = openedApp ?? app
                    _ = targetApp.activate(options: [.activateAllWindows])
                    if let error {
                        focusLogger.error("NSWorkspace activation failed for \(window.summary, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        completion("NSWorkspace activation failed: \(error.localizedDescription)")
                    } else {
                        focusLogger.info("NSWorkspace activation requested for \(window.summary, privacy: .public)")
                        completion(nil)
                    }
                }
            }
            return
        }

        _ = app.activate(options: [.activateAllWindows])
        focusLogger.info("NSRunningApplication activation fallback used for \(window.summary, privacy: .public)")
        completion("App has no bundle URL; used NSRunningApplication.activate fallback")
    }

    private func performSingleFocusAttempt(
        _ window: WindowReference,
        diagnostics: [String],
        completion: @escaping (WindowActionResult) -> Void
    ) {
        var nextDiagnostics = diagnostics
        let attemptDiagnostic = performAXFocusStep(window, attempt: 1)
        nextDiagnostics.append(attemptDiagnostic)
        focusLogger.info("\(attemptDiagnostic, privacy: .public)")

        if focusVerifier.verifiesFocus(for: window) {
            focusLogger.info("Focus verified for \(window.summary, privacy: .public)")
        } else {
            let diagnostic = "Focus not immediately verified after accepted request: \(nextDiagnostics.joined(separator: "; "))"
            focusLogger.info("\(diagnostic, privacy: .public)")
        }

        completion(.focused)
    }

    private func performAXFocusStep(_ window: WindowReference, attempt: Int) -> String {
        guard let element = window.axElement else {
            return "attempt \(attempt): bound window handle is not an Accessibility window"
        }
        let appElement = AXElementSafety.applicationElement(pid: window.pid)

        let mainDiagnostic = setTargetAsMain(window)
        let frontmostError = AXUIElementSetAttributeValue(
            appElement,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        let raiseError = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        let focusError = AXUIElementSetAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            element
        )

        return "attempt \(attempt): \(mainDiagnostic), frontmost \(frontmostError.readableDescription), raise \(raiseError.readableDescription), focusedWindow \(focusError.readableDescription)"
    }

    private func setTargetAsMain(_ window: WindowReference) -> String {
        guard let element = window.axElement else {
            return "AXMain unavailable: bound window handle is not an Accessibility window"
        }
        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(
            element,
            kAXMainAttribute as CFString,
            &settable
        )
        guard settableError == .success, settable.boolValue else {
            return "AXMain not settable (\(settableError.readableDescription))"
        }

        let error = AXUIElementSetAttributeValue(
            element,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        return "AXMain \(error.readableDescription)"
    }

    private func restoreIfMinimized(_ window: WindowReference) -> WindowActionResult {
        guard let element = window.axElement else {
            focusLogger.error("Restore check failed for \(window.summary, privacy: .public): bound window handle is not an Accessibility window")
            return .failed("Bound window handle is not an Accessibility window")
        }
        guard let isMinimized = AXAttributeReader.boolAttribute(kAXMinimizedAttribute, from: element), isMinimized else {
            focusLogger.debug("Window is not minimized: \(window.summary, privacy: .public)")
            return .focused
        }
        focusLogger.info("Window is minimized; restore requested for \(window.summary, privacy: .public)")

        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(
            element,
            kAXMinimizedAttribute as CFString,
            &settable
        )
        guard settableError == .success, settable.boolValue else {
            focusLogger.error("Restore unsupported for \(window.summary, privacy: .public): settable \(settableError.readableDescription, privacy: .public)")
            return .unsupported("Window is minimized but cannot be restored through Accessibility")
        }

        let error = AXUIElementSetAttributeValue(
            element,
            kAXMinimizedAttribute as CFString,
            kCFBooleanFalse
        )
        guard error == .success else {
            focusLogger.error("Restore failed for \(window.summary, privacy: .public): \(error.readableDescription, privacy: .public)")
            return .failed("Could not restore minimized window (\(error.readableDescription))")
        }
        focusLogger.info("Restored minimized window \(window.summary, privacy: .public)")
        return .focused
    }

}
