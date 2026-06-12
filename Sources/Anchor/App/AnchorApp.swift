import SwiftUI
import os

private let appLogger = AnchorLog.app

@main
struct AnchorApp: App {
    private static let defaultSlotIDs = SlotDefaults.enabledSlotIDs

    @StateObject private var permissionService: AccessibilityPermissionService
    @StateObject private var slotStore: WindowSlotStore
    @StateObject private var hotKeyManager: HotKeyManager
    @StateObject private var optionDoubleTapSettingsStore: OptionDoubleTapSettingsStore
    @StateObject private var statusItemController: StatusItemController

    init() {
        appLogger.info("Anchor app initializing with \(Self.defaultSlotIDs.count) slots")
        let permissionService = AccessibilityPermissionService()
        let windowService = AXWindowService()
        let focusService = WindowFocusService()
        let slotStore = WindowSlotStore(
            slotIDs: Self.defaultSlotIDs,
            windowService: windowService,
            focusService: focusService
        )
        let hotKeyManager = HotKeyManager(
            slotIDs: Self.defaultSlotIDs,
            registrar: CarbonHotKeyRegistrar()
        )
        let optionDoubleTapSettingsStore = OptionDoubleTapSettingsStore()
        let statusItemController = StatusItemController(
            permissionService: permissionService,
            windowService: windowService,
            slotStore: slotStore,
            hotKeyManager: hotKeyManager,
            optionDoubleTapSettingsStore: optionDoubleTapSettingsStore
        )

        hotKeyManager.start { intent in
            switch intent {
            case .focusSlot(let slotID):
                appLogger.info("Handling hotkey intent: focus slot \(slotID)")
                slotStore.activate(slotID: slotID)
            }
        }

        #if DEBUG
        LaunchAutomation.scheduleIfNeeded(
            arguments: CommandLine.arguments,
            statusItemController: statusItemController
        )
        #endif

        _permissionService = StateObject(wrappedValue: permissionService)
        _slotStore = StateObject(wrappedValue: slotStore)
        _hotKeyManager = StateObject(wrappedValue: hotKeyManager)
        _optionDoubleTapSettingsStore = StateObject(wrappedValue: optionDoubleTapSettingsStore)
        _statusItemController = StateObject(wrappedValue: statusItemController)
        appLogger.info("Anchor app initialized")
    }

    var body: some Scene {
        Settings {
            SettingsView(
                permissionService: permissionService,
                hotKeyManager: hotKeyManager,
                optionDoubleTapSettingsStore: optionDoubleTapSettingsStore
            )
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appLogger.info("Command action: open settings")
                    statusItemController.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
