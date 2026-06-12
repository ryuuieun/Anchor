import AppKit
import Carbon
import XCTest
@testable import Anchor

final class ModifierRecorderNSViewTests: XCTestCase {
    func testFlagsChangedSequenceFinishesOnFirstReleaseWithoutRecordingResidualChord() throws {
        let view = ModifierRecorderNSView(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        var beginCount = 0
        var records: [HotKeyModifiers] = []
        var endCount = 0

        view.onBeginRecording = {
            beginCount += 1
        }
        view.onRecord = { modifiers in
            records.append(modifiers)
        }
        view.onEndRecording = {
            endCount += 1
        }

        view.mouseDown(with: try mouseDownEvent())
        view.flagsChanged(with: try flagsChangedEvent([.control], keyCode: kVK_Control))
        view.flagsChanged(with: try flagsChangedEvent([.control, .option], keyCode: kVK_Option))
        view.flagsChanged(with: try flagsChangedEvent([.control, .option, .command], keyCode: kVK_Command))
        view.flagsChanged(with: try flagsChangedEvent([.option, .command], keyCode: kVK_Control))

        XCTAssertEqual(beginCount, 1)
        XCTAssertEqual(records, [
            [.control],
            [.control, .option],
            [.control, .option, .command]
        ])
        XCTAssertEqual(endCount, 1)

        view.flagsChanged(with: try flagsChangedEvent([.option], keyCode: kVK_Command))
        view.flagsChanged(with: try flagsChangedEvent([], keyCode: kVK_Option))

        XCTAssertEqual(records.last, [.control, .option, .command])
        XCTAssertEqual(endCount, 1)
    }

    func testKeyUpFinishesRecordingAndCommitsLastRecordedChordOnlyOnce() throws {
        let view = ModifierRecorderNSView(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        var records: [HotKeyModifiers] = []
        var endCount = 0

        view.onRecord = { modifiers in
            records.append(modifiers)
        }
        view.onEndRecording = {
            endCount += 1
        }

        view.mouseDown(with: try mouseDownEvent())
        view.flagsChanged(with: try flagsChangedEvent([.option], keyCode: kVK_Option))
        view.flagsChanged(with: try flagsChangedEvent([.option, .command], keyCode: kVK_Command))
        view.keyUp(with: try keyUpEvent(keyCode: kVK_ANSI_A))
        view.flagsChanged(with: try flagsChangedEvent([.option], keyCode: kVK_Command))

        XCTAssertEqual(records, [
            [.option],
            [.option, .command]
        ])
        XCTAssertEqual(endCount, 1)
    }

    private func mouseDownEvent() throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
    }

    private func flagsChangedEvent(
        _ modifierFlags: NSEvent.ModifierFlags,
        keyCode: Int
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ))
    }

    private func keyUpEvent(keyCode: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ))
    }
}
