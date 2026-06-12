import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    static let defaultContentSize = NSSize(width: 560, height: 340)

    init(
        permissionService: AccessibilityPermissionService,
        hotKeyManager: HotKeyManager,
        optionDoubleTapSettingsStore: OptionDoubleTapSettingsStore
    ) {
        let rootView = SettingsView(
            permissionService: permissionService,
            hotKeyManager: hotKeyManager,
            optionDoubleTapSettingsStore: optionDoubleTapSettingsStore
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Anchor Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.defaultContentSize)
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else {
            return
        }

        if !window.isVisible {
            window.center()
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func captureContent(to url: URL) throws {
        guard let contentView = window?.contentView else {
            throw captureError("Settings window has no content view")
        }

        contentView.layoutSubtreeIfNeeded()

        guard let representation = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            throw captureError("Could not allocate bitmap representation")
        }

        contentView.cacheDisplay(in: contentView.bounds, to: representation)

        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw captureError("Could not encode settings screenshot as PNG")
        }

        try data.write(to: url, options: .atomic)
    }

    private func captureError(_ message: String) -> NSError {
        NSError(
            domain: "Anchor.SettingsWindowCapture",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
