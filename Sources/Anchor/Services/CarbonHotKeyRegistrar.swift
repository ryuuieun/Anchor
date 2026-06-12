import Carbon
import Foundation
import os

private let carbonHotKeyLogger = AnchorLog.hotkeys

final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    private let signature: OSType = 0x574D534C

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var intentByID: [UInt32: HotKeyIntent] = [:]
    private var handler: ((HotKeyIntent) -> Void)?

    deinit {
        unregisterAll()
    }

    func register(_ definitions: [HotKeyDefinition], handler: @escaping (HotKeyIntent) -> Void) throws {
        carbonHotKeyLogger.info("Carbon registrar registering \(definitions.count) hotkeys")
        unregisterAll()
        self.handler = handler
        do {
            intentByID = try Self.makeIntentMap(from: definitions)
            try installEventHandlerIfNeeded()

            hotKeyRefs = try HotKeyRegistrationTransaction.register(
                definitions,
                register: { [signature] definition in
                    let carbonKeyCode = try CarbonHotKeyMapping.keyCode(for: definition.key)
                    let carbonModifiers = CarbonHotKeyMapping.modifiers(for: definition.modifiers)
                    let hotKeyID = EventHotKeyID(signature: signature, id: definition.id)
                    var hotKeyRef: EventHotKeyRef?

                    let status = RegisterEventHotKey(
                        carbonKeyCode,
                        carbonModifiers,
                        hotKeyID,
                        GetEventDispatcherTarget(),
                        0,
                        &hotKeyRef
                    )

                    guard status == noErr, let hotKeyRef else {
                        carbonHotKeyLogger.error("RegisterEventHotKey failed for \(definition.label, privacy: .public) status=\(status)")
                        throw HotKeyRegistrationError.registrationFailed(definition, status)
                    }
                    carbonHotKeyLogger.info("Registered global hotkey \(definition.label, privacy: .public)")
                    return hotKeyRef
                },
                unregister: { ref in
                    UnregisterEventHotKey(ref)
                }
            )
        } catch {
            carbonHotKeyLogger.error("Carbon registrar registration failed: \(error.localizedDescription, privacy: .public)")
            unregisterAll()
            throw error
        }
    }

    private static func makeIntentMap(from definitions: [HotKeyDefinition]) throws -> [UInt32: HotKeyIntent] {
        var intents: [UInt32: HotKeyIntent] = [:]
        for definition in definitions {
            guard intents[definition.id] == nil else {
                throw HotKeyRegistrationError.duplicateID(definition.id)
            }
            intents[definition.id] = definition.intent
        }
        return intents
    }

    func unregisterAll() {
        if !hotKeyRefs.isEmpty || eventHandler != nil {
            carbonHotKeyLogger.info("Unregistering \(self.hotKeyRefs.count) global hotkeys")
        }
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        intentByID.removeAll()
        handler = nil

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
            carbonHotKeyLogger.debug("Removed Carbon hotkey event handler")
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else {
            carbonHotKeyLogger.debug("Carbon hotkey event handler already installed")
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                let registrar = Unmanaged<CarbonHotKeyRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                registrar.handle(event: event)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            carbonHotKeyLogger.error("InstallEventHandler failed status=\(status)")
            throw HotKeyRegistrationError.eventHandlerInstallFailed(status)
        }
        carbonHotKeyLogger.info("Installed Carbon hotkey event handler")
    }

    private func handle(event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, let intent = intentByID[hotKeyID.id] else {
            carbonHotKeyLogger.error("Ignored Carbon hotkey event id=\(hotKeyID.id) status=\(status)")
            return
        }

        carbonHotKeyLogger.debug("Carbon hotkey event id=\(hotKeyID.id) received")
        DispatchQueue.main.async { [weak self] in
            self?.handler?(intent)
        }
    }
}
