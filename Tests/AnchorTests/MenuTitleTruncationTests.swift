import AppKit
import XCTest
@testable import Anchor

final class MenuTitleTruncationTests: XCTestCase {
    func testLongMenuTitleIsTruncatedToRequestedRenderedWidth() {
        let font = NSFont.menuFont(ofSize: 0)
        let title = "Slot 3: Obsidian - ITC_Study_Table_of_Contents - CS - Obsidian 1.12.7 (Bound)"
        let maxWidth: CGFloat = 210

        let truncated = title.truncatedForMenu(maxWidth: maxWidth, font: font)

        XCTAssertTrue(truncated.hasSuffix("..."))
        XCTAssertLessThanOrEqual(renderedWidth(of: truncated, font: font), maxWidth)
        XCTAssertLessThan(truncated.count, title.count)
    }

    func testShortMenuTitleIsPreserved() {
        let font = NSFont.menuFont(ofSize: 0)
        let title = "Slot 1: Codex - Codex (Bound)"

        XCTAssertEqual(title.truncatedForMenu(maxWidth: 210, font: font), title)
    }

    private func renderedWidth(of title: String, font: NSFont) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: font]).width
    }
}
