import Foundation

struct FocusedWindowMatchPolicy {
    static func targetApplicationCanOwnFocusedWindow(
        targetPID: pid_t,
        ownPID: pid_t,
        axFocusedApplicationPID: pid_t?,
        workspaceFrontmostPID: pid_t?
    ) -> Bool {
        guard targetPID > 0, targetPID != ownPID else {
            return false
        }

        if axFocusedApplicationPID == targetPID {
            return true
        }

        return workspaceFrontmostPID == targetPID
    }
}
