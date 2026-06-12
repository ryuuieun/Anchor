import AppKit
import Foundation

private let slotBindingPopupLogger = AnchorLog.menu

protocol SlotBindingPopupPresenting: AnyObject {
    func show(for window: WindowReference, slots: [WindowSlot])
}

final class SlotBindingPopupController: NSObject, NSMenuDelegate, SlotBindingPopupPresenting {
    private let menuItemTitleMaxWidth: CGFloat = 260

    private let slotStore: WindowSlotStore
    private var pendingWindow: WindowReference?
    private var activeMenu: NSMenu?

    init(slotStore: WindowSlotStore) {
        self.slotStore = slotStore
        super.init()
    }

    func show(for window: WindowReference, slots: [WindowSlot]) {
        show(for: window, slots: slots, at: NSEvent.mouseLocation)
    }

    func show(for window: WindowReference, slots: [WindowSlot], at location: NSPoint) {
        pendingWindow = window

        let menu = makeMenu(slots: slots)
        activeMenu = menu
        slotBindingPopupLogger.info("Showing slot binding popup for \(window.summary, privacy: .public)")
        menu.popUp(positioning: nil, at: location, in: nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === activeMenu else {
            return
        }

        DispatchQueue.main.async { [weak self, weak menu] in
            guard let self, let menu, menu === self.activeMenu else {
                return
            }

            self.pendingWindow = nil
            self.activeMenu = nil
            slotBindingPopupLogger.debug("Slot binding popup closed")
        }
    }

    private func makeMenu(slots: [WindowSlot]) -> NSMenu {
        let menu = NSMenu(title: "Bind Window to Slot")
        menu.autoenablesItems = false
        menu.delegate = self

        let sortedSlots = WindowSlotMenuModel.sortedSlots(slots)
        guard !sortedSlots.isEmpty else {
            let item = NSMenuItem(title: "No Slots Available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return menu
        }

        for slot in sortedSlots {
            let item = NSMenuItem(
                title: slot.bindMenuTitle.truncatedForMenu(maxWidth: menuItemTitleMaxWidth),
                action: #selector(bindSlot(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = slot.id
            item.isEnabled = true
            if item.title != slot.bindMenuTitle {
                item.toolTip = slot.bindMenuTitle
            }
            menu.addItem(item)
        }

        return menu
    }

    @objc private func bindSlot(_ sender: NSMenuItem) {
        guard let pendingWindow else {
            slotBindingPopupLogger.error("Ignored popup bind action because no window is pending")
            return
        }

        let window = pendingWindow
        self.pendingWindow = nil
        activeMenu = nil
        slotBindingPopupLogger.info("Popup action: bind captured window to slot \(sender.tag)")
        slotStore.bindWindow(window, to: sender.tag)
    }

    #if DEBUG
    var pendingWindowForTesting: WindowReference? {
        pendingWindow
    }

    func prepareMenuForTesting(for window: WindowReference, slots: [WindowSlot]) -> NSMenu {
        pendingWindow = window
        let menu = makeMenu(slots: slots)
        activeMenu = menu
        return menu
    }

    func bindSlotForTesting(_ slotID: Int) {
        let item = NSMenuItem(title: "Slot \(slotID)", action: nil, keyEquivalent: "")
        item.tag = slotID
        bindSlot(item)
    }
    #endif
}
