import AppKit
import Combine
import Foundation
import os

private let menuLogger = AnchorLog.menu

final class StatusItemController: NSObject, ObservableObject, NSMenuDelegate {
    private let menuItemTitleMaxWidth: CGFloat = 210

    private let permissionService: AccessibilityPermissionService
    private let slotStore: WindowSlotStore
    private let hotKeyManager: HotKeyManager

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let menuStatusRefreshQueue = DispatchQueue(
        label: "dev.anchor.menu-status-refresh",
        qos: .userInitiated
    )
    private var settingsWindowController: SettingsWindowController?
    private var isMenuStatusRefreshScheduled = false
    private var menuRebuildGate = MenuRebuildGate()
    private var cancellables = Set<AnyCancellable>()

    init(
        permissionService: AccessibilityPermissionService,
        slotStore: WindowSlotStore,
        hotKeyManager: HotKeyManager
    ) {
        self.permissionService = permissionService
        self.slotStore = slotStore
        self.hotKeyManager = hotKeyManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        rebuildMenu()
        observeStateChanges()
        menuLogger.info("Status item controller initialized")
    }

    deinit {
        menuLogger.info("Removing status item")
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        guard let button = statusItem.button else {
            menuLogger.error("Status item button is unavailable")
            return
        }
        button.title = ""
        button.toolTip = "Anchor"
        button.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Window slots")
        button.imagePosition = .imageOnly
    }

    private func observeStateChanges() {
        Publishers.MergeMany(
            slotStore.$slots.map { _ in () }.eraseToAnyPublisher(),
            slotStore.$lastMessage.map { _ in () }.eraseToAnyPublisher(),
            hotKeyManager.$statusMessage.map { _ in () }.eraseToAnyPublisher(),
            permissionService.$isTrusted.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst()
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.requestMenuRebuild()
        }
        .store(in: &cancellables)
    }

    private func requestMenuRebuild() {
        if menuRebuildGate.requestRebuild() {
            menuLogger.debug("Menu rebuild requested while closed; rebuilding immediately")
            rebuildMenu()
        } else {
            menuLogger.debug("Menu rebuild requested while open; deferring until close")
        }
    }

    private func rebuildMenu() {
        let orderedSlots = sortedSlots
        let boundSlots = orderedSlots.filter { $0.window != nil }
        let bindableSlots = WindowSlotMenuModel.bindableSlots(from: slotStore.slots)
        menuLogger.debug(
            "Rebuilding menu: boundSlots=\(boundSlots.count), bindableSlots=\(bindableSlots.count), accessibilityTrusted=\(self.permissionService.isTrusted)"
        )

        menu.removeAllItems()

        for slot in boundSlots {
            addBoundSlotItem(slot)
        }

        if !boundSlots.isEmpty {
            menu.addItem(.separator())
        }
        addBindFocusedWindowMenu(bindableSlots: bindableSlots)

        menu.addItem(.separator())
        addActionItem("Settings...", action: #selector(openSettings))
        addActionItem("Clear All Slots", action: #selector(clearAllSlots))
        addActionItem("Quit", action: #selector(quit))
    }

    private func addBoundSlotItem(_ slot: WindowSlot) {
        guard let window = slot.window else {
            return
        }

        let slotItem = makeMenuItem(title: slot.menuTitle, action: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        addDisabledItem("App: \(window.appName)", to: submenu)
        addDisabledItem("Window: \(window.displayTitle)", to: submenu)
        addDisabledItem("Status: \(slot.status.displayText)", to: submenu)
        submenu.addItem(.separator())
        addActionItem("Switch to Slot \(slot.id)", action: #selector(switchSlot(_:)), tag: slot.id, to: submenu)
        addActionItem("Clear Slot", action: #selector(clearSlot(_:)), tag: slot.id, to: submenu)

        slotItem.submenu = submenu
        menu.addItem(slotItem)
    }

    private func addBindFocusedWindowMenu(bindableSlots: [WindowSlot]) {
        let bindItem = makeMenuItem(title: "Bind Focused Window", action: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        for slot in bindableSlots {
            addActionItem(slot.bindMenuTitle, action: #selector(bindSlot(_:)), tag: slot.id, to: submenu)
        }

        bindItem.submenu = submenu
        menu.addItem(bindItem)
    }

    private var sortedSlots: [WindowSlot] {
        WindowSlotMenuModel.sortedSlots(slotStore.slots)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuLogger.info("Menu will open")
        menuRebuildGate.menuWillOpen()
        permissionService.refresh()
        rebuildMenu()
        scheduleMenuStatusRefresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        let shouldRebuild = menuRebuildGate.menuDidClose()
        menuLogger.debug("Menu did close; deferredRebuild=\(shouldRebuild)")
        if shouldRebuild {
            rebuildMenu()
        }
    }

    private func scheduleMenuStatusRefresh() {
        guard !isMenuStatusRefreshScheduled else {
            menuLogger.debug("Menu status refresh already scheduled")
            return
        }

        isMenuStatusRefreshScheduled = true
        menuLogger.debug("Scheduling menu status refresh")
        let requests = slotStore.makeStatusRefreshRequests()
        guard !requests.isEmpty else {
            isMenuStatusRefreshScheduled = false
            menuLogger.debug("Menu status refresh skipped because no slots are bound")
            return
        }

        menuStatusRefreshQueue.async { [weak self] in
            guard let self else {
                return
            }
            let results = slotStore.validateStatusRefreshRequests(requests)
            DispatchQueue.main.async {
                self.isMenuStatusRefreshScheduled = false
                self.slotStore.applyStatusRefreshResults(results)
                menuLogger.debug("Menu status refresh completed")
                self.requestMenuRebuild()
                #if DEBUG
                self.onMenuStatusRefreshAppliedForTesting?()
                #endif
            }
        }
    }

    @discardableResult
    private func addDisabledItem(_ title: String, to menu: NSMenu? = nil) -> NSMenuItem {
        let item = makeMenuItem(title: title, action: nil)
        item.isEnabled = false
        (menu ?? self.menu).addItem(item)
        return item
    }

    @discardableResult
    private func addActionItem(
        _ title: String,
        action: Selector,
        tag: Int = 0,
        to menu: NSMenu? = nil
    ) -> NSMenuItem {
        let item = makeMenuItem(title: title, action: action)
        item.target = self
        item.tag = tag
        item.isEnabled = true
        (menu ?? self.menu).addItem(item)
        return item
    }

    private func makeMenuItem(title: String, action: Selector?) -> NSMenuItem {
        let displayTitle = title.truncatedForMenu(maxWidth: menuItemTitleMaxWidth)
        let item = NSMenuItem(title: displayTitle, action: action, keyEquivalent: "")
        if displayTitle != title {
            item.toolTip = title
        }
        return item
    }

    @objc private func switchSlot(_ sender: NSMenuItem) {
        menuLogger.info("Menu action: switch slot \(sender.tag)")
        slotStore.activate(slotID: sender.tag)
        requestMenuRebuild()
    }

    @objc private func bindSlot(_ sender: NSMenuItem) {
        menuLogger.info("Menu action: bind focused window to slot \(sender.tag)")
        slotStore.bindFocusedWindow(to: sender.tag)
        requestMenuRebuild()
    }

    @objc private func clearSlot(_ sender: NSMenuItem) {
        menuLogger.info("Menu action: clear slot \(sender.tag)")
        slotStore.clear(slotID: sender.tag)
        requestMenuRebuild()
    }

    @objc private func clearAllSlots() {
        menuLogger.info("Menu action: clear all slots")
        slotStore.clearAll()
        requestMenuRebuild()
    }

    func showSettings() {
        if settingsWindowController == nil {
            menuLogger.info("Creating settings window controller")
            settingsWindowController = SettingsWindowController(
                permissionService: permissionService,
                hotKeyManager: hotKeyManager
            )
        }

        menuLogger.info("Showing settings window")
        settingsWindowController?.show()
    }

    func captureSettingsWindowContent(to url: URL) throws {
        menuLogger.debug("Capturing settings window content to \(url.path, privacy: .public)")
        showSettings()
        try settingsWindowController?.captureContent(to: url)
    }

    @objc private func openSettings() {
        menuLogger.info("Menu action: open settings")
        showSettings()
    }

    @objc private func quit() {
        menuLogger.info("Menu action: quit")
        NSApp.terminate(nil)
    }

    #if DEBUG
    var menuForTesting: NSMenu {
        menu
    }

    var menuTitlesForTesting: [String] {
        menu.items.map(\.title)
    }

    var onMenuStatusRefreshAppliedForTesting: (() -> Void)?
    #endif
}

extension String {
    func truncatedForMenu(maxWidth: CGFloat, font: NSFont = .menuFont(ofSize: 0)) -> String {
        guard renderedWidth(font: font) > maxWidth else {
            return self
        }

        let ellipsis = "..."
        guard maxWidth > ellipsis.renderedWidth(font: font) else {
            return ellipsis
        }

        var low = 0
        var high = count
        var best = ellipsis

        while low <= high {
            let middle = (low + high) / 2
            let candidate = String(prefix(middle)) + ellipsis
            if candidate.renderedWidth(font: font) <= maxWidth {
                best = candidate
                low = middle + 1
            } else {
                high = middle - 1
            }
        }

        return best
    }

    private func renderedWidth(font: NSFont) -> CGFloat {
        (self as NSString).size(withAttributes: [.font: font]).width
    }
}
