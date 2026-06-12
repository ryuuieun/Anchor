import ApplicationServices
import Foundation
import os

private let permissionLogger = AnchorLog.permissions

final class AccessibilityPermissionService: ObservableObject {
    @Published private(set) var isTrusted: Bool

    init() {
        isTrusted = AXIsProcessTrusted()
        permissionLogger.info("Accessibility permission initialized: trusted=\(self.isTrusted)")
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
            permissionLogger.info("Accessibility permission changed: trusted=\(trusted)")
        } else {
            permissionLogger.debug("Accessibility permission unchanged: trusted=\(trusted)")
        }
    }

}
