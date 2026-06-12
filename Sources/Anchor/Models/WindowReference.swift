import CoreGraphics
import Foundation

protocol WindowElementHandle: AnyObject {
    func isSameWindow(as other: WindowElementHandle) -> Bool
}

struct WindowFingerprint: Equatable {
    let pid: pid_t
    let bundleIdentifier: String?
    let title: String
    let role: String
    let subrole: String?
    let identifier: String?
    let position: CGPoint?
    let size: CGSize?
    let cgWindowID: CGWindowID?
    let cgBounds: CGRect?
    let cgLayer: Int?
}

final class WindowReference {
    var handle: WindowElementHandle
    var fingerprint: WindowFingerprint
    let pid: pid_t
    let appName: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    var title: String
    let role: String
    var subrole: String?
    var identifier: String?

    init(
        handle: WindowElementHandle,
        pid: pid_t,
        appName: String,
        bundleIdentifier: String?,
        bundleURL: URL?,
        title: String,
        role: String,
        subrole: String?,
        identifier: String?,
        fingerprint: WindowFingerprint
    ) {
        self.handle = handle
        self.fingerprint = fingerprint
        self.pid = pid
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.title = title
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Window" : trimmed
    }

    var summary: String {
        "\(appName) - \(displayTitle)"
    }

    func isSameWindow(as other: WindowReference) -> Bool {
        pid == other.pid && handle.isSameWindow(as: other.handle)
    }

    @discardableResult
    func updateSnapshot(
        handle newHandle: WindowElementHandle,
        title: String,
        subrole: String?,
        identifier: String?,
        fingerprint: WindowFingerprint
    ) -> Bool {
        let changed = !handle.isSameWindow(as: newHandle)
            || self.title != title
            || self.subrole != subrole
            || self.identifier != identifier
            || self.fingerprint != fingerprint
        handle = newHandle
        self.title = title
        self.subrole = subrole
        self.identifier = identifier
        self.fingerprint = fingerprint
        return changed
    }
}

enum WindowSlotStatus: Equatable {
    case empty
    case bound
    case switching
    case unavailable(String)
    case accessibilityUnavailable(String)
    case actionFailed(String)

    var displayText: String {
        switch self {
        case .empty:
            return "Empty"
        case .bound:
            return "Bound"
        case .switching:
            return "Switching"
        case .unavailable(let message):
            return "Unavailable: \(message)"
        case .accessibilityUnavailable(let message):
            return "Accessibility unavailable: \(message)"
        case .actionFailed(let message):
            return "Action failed: \(message)"
        }
    }
}

struct WindowSlot: Identifiable {
    let id: Int
    var window: WindowReference?
    var status: WindowSlotStatus = .empty

    var menuTitle: String {
        guard let window else {
            return "Slot \(id): Empty"
        }
        return "Slot \(id): \(window.appName) - \(window.displayTitle) (\(status.displayText))"
    }

    var bindMenuTitle: String {
        guard let window else {
            return "Slot \(id)"
        }
        return "Slot \(id) - \(window.appName) - \(window.displayTitle)"
    }
}

enum WindowValidationResult: Equatable {
    case valid
    case updatedFingerprint
    case temporarilyUnavailable(String)
    case accessibilityUnavailable(String)
    case missing(String)
    case ambiguous(String)
}

enum WindowCaptureResult {
    case success(WindowReference)
    case failure(String)
}

enum WindowActionResult: Equatable {
    case focused
    case unsupported(String)
    case failed(String)
    case focusVerificationFailed(String)

    var statusMessage: String {
        switch self {
        case .focused:
            return "Focused window"
        case .unsupported(let reason):
            return reason
        case .failed(let reason):
            return reason
        case .focusVerificationFailed(let reason):
            return reason
        }
    }
}
