import SwiftUI
import os

private let settingsLogger = AnchorLog.settings

struct SettingsView: View {
    @ObservedObject var permissionService: AccessibilityPermissionService
    @ObservedObject var hotKeyManager: HotKeyManager

    var body: some View {
        Form {
            Section("Permissions") {
                Text("Accessibility: \(permissionService.isTrusted ? "Granted" : "Not granted")")
            }

            Section("Hotkeys") {
                HotKeyModifierEditor(
                    title: "Switch",
                    modifiers: hotKeyManager.configuration.switchModifiers
                ) { modifiers in
                    settingsLogger.info("Settings action: update switch modifiers to \(modifiers.displayLabel, privacy: .public)")
                    hotKeyManager.updateModifiers(for: .switchSlot, modifiers: modifiers)
                }

                Button("Reset Hotkeys") {
                    settingsLogger.info("Settings action: reset hotkeys")
                    hotKeyManager.resetToDefaults()
                }

                Text(hotKeyManager.statusMessage)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
    }
}

private struct HotKeyModifierEditor: View {
    let title: String
    let modifiers: HotKeyModifiers
    let onChange: (HotKeyModifiers) -> Void

    @State private var recordingDraft = ModifierRecordingDraft()

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 56, alignment: .leading)

            ModifierRecorderView(
                modifiers: recordingDraft.displayModifiers(fallback: modifiers),
                isRecording: recordingDraft.isRecording,
                onBeginRecording: {
                    settingsLogger.info("Modifier recording started for \(title, privacy: .public)")
                    recordingDraft.begin()
                },
                onRecord: { recordedModifiers in
                    settingsLogger.debug("Modifier recording draft for \(title, privacy: .public): \(recordedModifiers.displayLabel, privacy: .public)")
                    recordingDraft.record(recordedModifiers)
                },
                onEndRecording: {
                    if let modifiers = recordingDraft.finish() {
                        settingsLogger.info("Modifier recording committed for \(title, privacy: .public): \(modifiers.displayLabel, privacy: .public)")
                        onChange(modifiers)
                    } else {
                        settingsLogger.info("Modifier recording ended for \(title, privacy: .public) without committed modifiers")
                    }
                }
            )
            .frame(width: 260, height: 30)
        }
    }
}
