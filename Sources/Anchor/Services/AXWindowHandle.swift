import ApplicationServices
import Foundation

final class AXWindowHandle: WindowElementHandle {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = AXElementSafety.applyMessagingTimeout(to: element)
    }

    func isSameWindow(as other: WindowElementHandle) -> Bool {
        guard let other = other as? AXWindowHandle else {
            return false
        }
        return CFEqual(element, other.element)
    }
}

extension WindowReference {
    var axElement: AXUIElement? {
        (handle as? AXWindowHandle)?.element
    }
}
