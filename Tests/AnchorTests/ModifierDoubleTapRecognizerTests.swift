import XCTest
@testable import Anchor

final class ModifierDoubleTapRecognizerTests: XCTestCase {
    private let configuration = ModifierDoubleTapConfiguration(
        maximumTapDuration: 0.25,
        maximumIntervalBetweenTaps: 0.35,
        triggerCooldown: 0.5
    )

    func testDoubleTapSameOptionKeyTriggersOnSecondRelease() {
        var recognizer = ModifierDoubleTapRecognizer(configuration: configuration)

        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.00)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.08)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.20)))
        XCTAssertTrue(recognizer.handle(option(.leftOption, isDown: false, at: 1.27)))
    }

    func testRightOptionDoubleTapTriggersIndependently() {
        var recognizer = ModifierDoubleTapRecognizer(configuration: configuration)

        XCTAssertFalse(recognizer.handle(option(.rightOption, isDown: true, at: 1.00)))
        XCTAssertFalse(recognizer.handle(option(.rightOption, isDown: false, at: 1.05)))
        XCTAssertFalse(recognizer.handle(option(.rightOption, isDown: true, at: 1.14)))
        XCTAssertTrue(recognizer.handle(option(.rightOption, isDown: false, at: 1.19)))
    }

    func testMixedOptionKeysDoNotTrigger() {
        var recognizer = ModifierDoubleTapRecognizer(configuration: configuration)

        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.00)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.05)))
        XCTAssertFalse(recognizer.handle(option(.rightOption, isDown: true, at: 1.12)))
        XCTAssertFalse(recognizer.handle(option(.rightOption, isDown: false, at: 1.18)))
    }

    func testLongPressCancelsTapSequence() {
        var recognizer = ModifierDoubleTapRecognizer(configuration: configuration)

        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.00)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.40)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.45)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.50)))
    }

    func testSecondTapAfterIntervalStartsNewSequenceInsteadOfTriggering() {
        var recognizer = ModifierDoubleTapRecognizer(configuration: configuration)

        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.00)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.05)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.50)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.55)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.70)))
        XCTAssertTrue(recognizer.handle(option(.leftOption, isDown: false, at: 1.75)))
    }

    func testDisallowedModifierCancelsSequence() {
        var recognizer = ModifierDoubleTapRecognizer(configuration: configuration)

        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.00)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.05)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, hasDisallowedModifiers: true, at: 1.15)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.20)))
    }

    func testCancelEventClearsPendingSequence() {
        var recognizer = ModifierDoubleTapRecognizer(configuration: configuration)

        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.00)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.05)))
        XCTAssertFalse(recognizer.handle(.cancel(timestamp: 1.10)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.15)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.20)))
    }

    func testCooldownSuppressesImmediateRetrigger() {
        var recognizer = ModifierDoubleTapRecognizer(configuration: configuration)

        triggerLeftOptionDoubleTap(on: &recognizer, startingAt: 1.00)
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.32)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.37)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: 1.45)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: 1.50)))
    }

    private func triggerLeftOptionDoubleTap(
        on recognizer: inout ModifierDoubleTapRecognizer,
        startingAt start: TimeInterval
    ) {
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: start)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: false, at: start + 0.05)))
        XCTAssertFalse(recognizer.handle(option(.leftOption, isDown: true, at: start + 0.15)))
        XCTAssertTrue(recognizer.handle(option(.leftOption, isDown: false, at: start + 0.20)))
    }

    private func option(
        _ key: ModifierDoubleTapKey,
        isDown: Bool,
        hasDisallowedModifiers: Bool = false,
        at timestamp: TimeInterval
    ) -> ModifierDoubleTapEvent {
        .optionChanged(
            key: key,
            isDown: isDown,
            hasDisallowedModifiers: hasDisallowedModifiers,
            timestamp: timestamp
        )
    }
}
