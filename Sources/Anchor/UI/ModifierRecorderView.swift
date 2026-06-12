import AppKit
import SwiftUI
import os

private let modifierRecorderLogger = AnchorLog.settings

struct ModifierRecorderView: NSViewRepresentable {
    let modifiers: HotKeyModifiers
    let isRecording: Bool
    let onBeginRecording: () -> Void
    let onRecord: (HotKeyModifiers) -> Void
    let onEndRecording: () -> Void

    func makeNSView(context: Context) -> ModifierRecorderNSView {
        let view = ModifierRecorderNSView()
        view.onBeginRecording = onBeginRecording
        view.onRecord = onRecord
        view.onEndRecording = onEndRecording
        return view
    }

    func updateNSView(_ nsView: ModifierRecorderNSView, context: Context) {
        nsView.modifiers = modifiers
        nsView.isRecording = isRecording
        nsView.onBeginRecording = onBeginRecording
        nsView.onRecord = onRecord
        nsView.onEndRecording = onEndRecording
        nsView.needsDisplay = true
    }
}

final class ModifierRecorderNSView: NSView {
    var modifiers: HotKeyModifiers = []
    var isRecording = false
    var onBeginRecording: (() -> Void)?
    var onRecord: ((HotKeyModifiers) -> Void)?
    var onEndRecording: (() -> Void)?
    private var recordingSession = ModifierRecordingSession()

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 260, height: 30)
    }

    override func mouseDown(with event: NSEvent) {
        modifierRecorderLogger.info("Modifier recorder mouse down; starting recording")
        window?.makeFirstResponder(self)
        recordingSession.reset()
        isRecording = true
        onBeginRecording?()
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            return
        }

        let nextModifiers = ModifierRecorderMapping.modifiers(from: event.modifierFlags)
        switch recordingSession.update(to: nextModifiers) {
        case .record(let nextModifiers):
            modifierRecorderLogger.debug("Modifier recorder observed modifiers \(nextModifiers.displayLabel, privacy: .public)")
            onRecord?(nextModifiers)
        case .finish:
            modifierRecorderLogger.debug("Modifier recorder observed release; finishing")
            finishRecording()
        case .ignore:
            modifierRecorderLogger.debug("Modifier recorder ignored unchanged modifier state")
            break
        }
        needsDisplay = true
    }

    override func keyUp(with event: NSEvent) {
        modifierRecorderLogger.debug("Modifier recorder key up; finishing")
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        modifierRecorderLogger.debug("Modifier recorder resigned first responder; finishing")
        finishRecording()
        return super.resignFirstResponder()
    }

    private func finishRecording() {
        guard isRecording else {
            return
        }

        isRecording = false
        recordingSession.reset()
        modifierRecorderLogger.info("Modifier recorder finished")
        onEndRecording?()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()

        let strokeColor: NSColor = isRecording ? .controlAccentColor : .separatorColor
        strokeColor.setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text = isRecording ? "Recording..." : "\(modifiers.displayLabel)+0-9"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textRect = NSRect(
            x: bounds.minX + 10,
            y: bounds.midY - attributed.size().height / 2,
            width: bounds.width - 20,
            height: attributed.size().height
        )
        attributed.draw(in: textRect)
    }
}
