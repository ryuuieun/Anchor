import Foundation

protocol WindowServiceProtocol: AnyObject {
    func captureFocusedWindow() -> WindowCaptureResult
    func validate(_ window: WindowReference) -> WindowValidationResult
    func refreshFingerprint(for window: WindowReference)
    func focusedWindowMatches(_ window: WindowReference) -> Bool
}

protocol WindowFocusServiceProtocol: AnyObject {
    func focus(_ window: WindowReference, completion: @escaping (WindowActionResult) -> Void)
}

protocol WindowLifecycleObserving: AnyObject {
    var onWindowInvalidated: ((WindowReference, String) -> Void)? { get set }

    func watch(_ window: WindowReference, slotID: Int) -> WindowLifecycleWatchResult
    func unwatchSlot(_ slotID: Int)
    func unwatchAll()
}
