import XCTest
@testable import Anchor

final class WindowSlotMenuTitleTests: XCTestCase {
    func testBindMenuTitleShowsEmptySlotState() {
        let slot = WindowSlot(id: 4)

        XCTAssertEqual(slot.bindMenuTitle, "Slot 4")
    }

    func testBindMenuTitleShowsBoundWindowSummary() {
        let slot = WindowSlot(
            id: 3,
            window: makeWindow(appName: "Obsidian", title: "ITC_Study_Table_of_Contents"),
            status: .bound
        )

        XCTAssertEqual(slot.bindMenuTitle, "Slot 3 - Obsidian - ITC_Study_Table_of_Contents")
    }

    func testBindableSlotsOnlyIncludesEmptySlotsInSlotOrder() {
        let slots = [
            WindowSlot(id: 3),
            WindowSlot(id: 1, window: makeWindow(appName: "Codex", title: "Codex"), status: .bound),
            WindowSlot(id: 0),
            WindowSlot(id: 2),
            WindowSlot(id: 9, window: makeWindow(appName: "Firefox", title: "ChatGPT"), status: .bound)
        ]

        XCTAssertEqual(WindowSlotMenuModel.bindableSlots(from: slots).map(\.id), [2, 3, 0])
    }
}

private func makeWindow(
    appName: String,
    title: String
) -> WindowReference {
    let handle = TestWindowElementHandle()
    let fingerprint = WindowFingerprint(
        pid: 10_000,
        bundleIdentifier: "dev.test.App",
        title: title,
        role: "AXWindow",
        subrole: "AXStandardWindow",
        identifier: nil,
        position: nil,
        size: nil,
        cgWindowID: nil,
        cgBounds: nil,
        cgLayer: nil
    )

    return WindowReference(
        handle: handle,
        pid: 10_000,
        appName: appName,
        bundleIdentifier: "dev.test.App",
        bundleURL: nil,
        title: title,
        role: "AXWindow",
        subrole: "AXStandardWindow",
        identifier: nil,
        fingerprint: fingerprint
    )
}

private final class TestWindowElementHandle: WindowElementHandle {
    func isSameWindow(as other: WindowElementHandle) -> Bool {
        other === self
    }
}
