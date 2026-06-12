import XCTest
@testable import Anchor

final class ModifierRecordingSessionTests: XCTestCase {
    func testRecordsGrowingModifierChordAndFinishesOnReleaseWithoutOverwriting() {
        var session = ModifierRecordingSession()

        XCTAssertEqual(session.update(to: [.control]), .record([.control]))
        XCTAssertEqual(session.update(to: [.control, .option]), .record([.control, .option]))
        XCTAssertEqual(
            session.update(to: [.control, .option, .command]),
            .record([.control, .option, .command])
        )

        XCTAssertEqual(session.update(to: [.option, .command]), .finish)
    }

    func testFinishesWhenAllModifiersAreReleased() {
        var session = ModifierRecordingSession()

        XCTAssertEqual(session.update(to: [.option]), .record([.option]))
        XCTAssertEqual(session.update(to: [.option, .command]), .record([.option, .command]))
        XCTAssertEqual(session.update(to: []), .finish)
    }

    func testIgnoresRepeatedModifierState() {
        var session = ModifierRecordingSession()

        XCTAssertEqual(session.update(to: [.option]), .record([.option]))
        XCTAssertEqual(session.update(to: [.option]), .ignore)
    }

    func testAnyModifierReleaseFinishesRecording() {
        var session = ModifierRecordingSession()

        XCTAssertEqual(session.update(to: [.control]), .record([.control]))
        XCTAssertEqual(session.update(to: [.control, .option]), .record([.control, .option]))
        XCTAssertEqual(
            session.update(to: [.control, .option, .command]),
            .record([.control, .option, .command])
        )
        XCTAssertEqual(session.update(to: [.control, .command]), .finish)
    }

    func testDraftDoesNotCommitUntilFinish() {
        var draft = ModifierRecordingDraft()

        draft.begin()
        draft.record([.control])
        draft.record([.control, .option])
        draft.record([.control, .option, .command])

        XCTAssertTrue(draft.isRecording)
        XCTAssertEqual(draft.pendingModifiers, [.control, .option, .command])
        XCTAssertEqual(draft.displayModifiers(fallback: [.option]), [.control, .option, .command])
        XCTAssertEqual(draft.finish(), [.control, .option, .command])
    }

    func testDraftCommitsOnlyOnceAndThenReturnsToFallbackDisplay() {
        var draft = ModifierRecordingDraft()

        draft.begin()
        draft.record([.option, .command])

        XCTAssertEqual(draft.finish(), [.option, .command])
        XCTAssertNil(draft.finish())
        XCTAssertFalse(draft.isRecording)
        XCTAssertNil(draft.pendingModifiers)
        XCTAssertEqual(draft.displayModifiers(fallback: [.control]), [.control])
    }

    func testDraftIgnoresRecordEventsOutsideRecording() {
        var draft = ModifierRecordingDraft()

        draft.record([.option, .command])

        XCTAssertNil(draft.pendingModifiers)
        XCTAssertNil(draft.finish())
    }
}
