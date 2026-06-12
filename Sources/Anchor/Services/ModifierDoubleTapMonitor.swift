import ApplicationServices
import Carbon
import Foundation

private let modifierDoubleTapLogger = AnchorLog.hotkeys

protocol ModifierDoubleTapMonitoring: AnyObject {
    var onDoubleTap: (() -> Void)? { get set }

    @discardableResult
    func start() -> Bool
    func stop()
}

final class ModifierDoubleTapMonitor: ModifierDoubleTapMonitoring {
    var onDoubleTap: (() -> Void)?

    private var recognizer: ModifierDoubleTapRecognizer
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let runLoop: CFRunLoop

    init(
        configuration: ModifierDoubleTapConfiguration = .optionBindingDefault,
        runLoop: CFRunLoop = CFRunLoopGetMain()
    ) {
        recognizer = ModifierDoubleTapRecognizer(configuration: configuration)
        self.runLoop = runLoop
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else {
            return true
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.eventMask,
            callback: Self.eventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            modifierDoubleTapLogger.error("Failed to create Option double-tap event tap")
            return false
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            modifierDoubleTapLogger.error("Failed to create Option double-tap run loop source")
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(runLoop, runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        modifierDoubleTapLogger.info("Started Option double-tap monitor")
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
            modifierDoubleTapLogger.info("Stopped Option double-tap monitor")
        }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            _ = recognizer.handle(.cancel(timestamp: Self.timestamp(from: event)))
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                modifierDoubleTapLogger.info("Re-enabled Option double-tap event tap")
            }

        case .flagsChanged:
            handleFlagsChanged(event)

        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            _ = recognizer.handle(.cancel(timestamp: Self.timestamp(from: event)))

        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let timestamp = Self.timestamp(from: event)

        guard let optionKey = Self.optionKey(for: keyCode) else {
            _ = recognizer.handle(.cancel(timestamp: timestamp))
            return
        }

        let didTrigger = recognizer.handle(
            .optionChanged(
                key: optionKey,
                isDown: event.flags.contains(.maskAlternate),
                hasDisallowedModifiers: Self.hasDisallowedModifiers(event.flags),
                timestamp: timestamp
            )
        )

        guard didTrigger else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onDoubleTap?()
        }
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<ModifierDoubleTapMonitor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        monitor.handle(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }

    private static var eventMask: CGEventMask {
        mask(for: .flagsChanged)
            | mask(for: .keyDown)
            | mask(for: .leftMouseDown)
            | mask(for: .rightMouseDown)
            | mask(for: .otherMouseDown)
    }

    private static func mask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(type.rawValue)
    }

    private static func optionKey(for keyCode: Int) -> ModifierDoubleTapKey? {
        switch keyCode {
        case kVK_Option:
            return .leftOption
        case kVK_RightOption:
            return .rightOption
        default:
            return nil
        }
    }

    private static func hasDisallowedModifiers(_ flags: CGEventFlags) -> Bool {
        let disallowedFlags: CGEventFlags = [
            .maskCommand,
            .maskControl,
            .maskShift,
            .maskSecondaryFn
        ]
        return !flags.intersection(disallowedFlags).isEmpty
    }

    private static func timestamp(from event: CGEvent) -> TimeInterval {
        TimeInterval(event.timestamp) / 1_000_000_000
    }
}
