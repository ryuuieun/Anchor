import Foundation

protocol HotKeyRegistrar: AnyObject {
    func register(_ definitions: [HotKeyDefinition], handler: @escaping (HotKeyIntent) -> Void) throws
    func unregisterAll()
}

enum HotKeyRegistrationError: LocalizedError {
    case unsupportedKey(PhysicalKey)
    case duplicateID(UInt32)
    case eventHandlerInstallFailed(OSStatus)
    case registrationFailed(HotKeyDefinition, OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedKey(let key):
            return "Unsupported key \(key)"
        case .duplicateID(let id):
            return "Duplicate hotkey registration id \(id)"
        case .eventHandlerInstallFailed(let status):
            return "Could not install hotkey event handler (OSStatus \(status))"
        case .registrationFailed(let definition, let status):
            return "Could not register \(definition.label) (OSStatus \(status))"
        }
    }
}
