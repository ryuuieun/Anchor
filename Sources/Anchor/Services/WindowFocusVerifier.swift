import ApplicationServices
import Foundation

protocol WindowFocusVerificationReading {
    func windowHandle(pid: pid_t, attribute: String) -> WindowElementHandle?
}

struct WindowFocusVerifier {
    let reader: WindowFocusVerificationReading

    func verifiesFocus(for window: WindowReference) -> Bool {
        if let focusedWindowHandle = reader.windowHandle(
            pid: window.pid,
            attribute: kAXFocusedWindowAttribute as String
        ), focusedWindowHandle.isSameWindow(as: window.handle) {
            return true
        }

        guard let mainWindowHandle = reader.windowHandle(
            pid: window.pid,
            attribute: kAXMainWindowAttribute as String
        ) else {
            return false
        }
        return mainWindowHandle.isSameWindow(as: window.handle)
    }
}

final class AXWindowFocusVerificationReader: WindowFocusVerificationReading {
    func windowHandle(pid: pid_t, attribute: String) -> WindowElementHandle? {
        let appElement = AXElementSafety.applicationElement(pid: pid)
        let result = AXAttributeReader.elementAttribute(attribute, from: appElement)
        guard let element = result.element else {
            return nil
        }
        return AXWindowHandle(element)
    }
}
