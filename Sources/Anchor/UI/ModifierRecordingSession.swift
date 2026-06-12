import Foundation

enum ModifierRecordingEvent: Equatable {
    case record(HotKeyModifiers)
    case finish
    case ignore
}

struct ModifierRecordingSession {
    private var observedModifiers: HotKeyModifiers = []

    mutating func reset() {
        observedModifiers = []
    }

    mutating func update(to nextModifiers: HotKeyModifiers) -> ModifierRecordingEvent {
        guard !nextModifiers.isEmpty else {
            reset()
            return .finish
        }

        let newlyPressed = HotKeyModifiers(
            rawValue: nextModifiers.rawValue & ~observedModifiers.rawValue
        )
        if !newlyPressed.isEmpty {
            observedModifiers = nextModifiers
            return .record(nextModifiers)
        }

        if nextModifiers != observedModifiers {
            reset()
            return .finish
        }

        return .ignore
    }
}

struct ModifierRecordingDraft {
    private(set) var isRecording = false
    private(set) var pendingModifiers: HotKeyModifiers?

    mutating func begin() {
        isRecording = true
        pendingModifiers = nil
    }

    mutating func record(_ modifiers: HotKeyModifiers) {
        guard isRecording else {
            return
        }
        pendingModifiers = modifiers
    }

    mutating func finish() -> HotKeyModifiers? {
        defer {
            isRecording = false
            pendingModifiers = nil
        }

        guard isRecording else {
            return nil
        }

        return pendingModifiers
    }

    func displayModifiers(fallback: HotKeyModifiers) -> HotKeyModifiers {
        pendingModifiers ?? fallback
    }
}
