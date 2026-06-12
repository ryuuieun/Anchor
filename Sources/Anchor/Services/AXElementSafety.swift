import ApplicationServices
import Foundation

enum AXElementSafety {
    static let messagingTimeout: Float = 0.35

    static func systemWideElement() -> AXUIElement {
        applyMessagingTimeout(to: AXUIElementCreateSystemWide())
    }

    static func applicationElement(pid: pid_t) -> AXUIElement {
        applyMessagingTimeout(to: AXUIElementCreateApplication(pid))
    }

    static func element(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return applyMessagingTimeout(to: value as! AXUIElement)
    }

    static func elements(from value: CFTypeRef?) -> [AXUIElement]? {
        guard let elements = value as? [AXUIElement] else {
            return nil
        }
        return elements.map { applyMessagingTimeout(to: $0) }
    }

    @discardableResult
    static func applyMessagingTimeout(to element: AXUIElement) -> AXUIElement {
        _ = AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }
}
