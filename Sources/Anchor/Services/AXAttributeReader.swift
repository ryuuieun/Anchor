import ApplicationServices
import CoreGraphics
import Foundation

enum AXAttributeReader {
    static func elementAttribute(_ attribute: String, from element: AXUIElement) -> (element: AXUIElement?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let axElement = AXElementSafety.element(from: value) else {
            return (nil, error)
        }
        return (axElement, error)
    }

    static func elementsAttribute(_ attribute: String, from element: AXUIElement) -> (elements: [AXUIElement]?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let elements = AXElementSafety.elements(from: value) else {
            return (nil, error)
        }
        return (elements, error)
    }

    static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        stringAttributeResult(attribute, from: element).value
    }

    static func stringAttributeIfAvailable(_ attribute: String, from element: AXUIElement) -> String? {
        let result = stringAttributeResult(attribute, from: element)
        guard result.error == .success else {
            return nil
        }
        return result.value
    }

    static func stringAttributeResult(_ attribute: String, from element: AXUIElement) -> (value: String?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return (nil, error)
        }
        return (value as? String, error)
    }

    static func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    static func pointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    static func sizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}
