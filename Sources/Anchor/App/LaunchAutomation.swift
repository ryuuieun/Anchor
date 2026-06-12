#if DEBUG
import Foundation

enum LaunchAutomation {
    static func scheduleIfNeeded(
        arguments: [String],
        statusItemController: StatusItemController
    ) {
        guard let screenshotPath = value(after: "--screenshot-settings", in: arguments) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            statusItemController.showSettings()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                do {
                    try statusItemController.captureSettingsWindowContent(
                        to: URL(fileURLWithPath: screenshotPath)
                    )
                } catch {
                    fputs("Anchor screenshot failed: \(error.localizedDescription)\n", stderr)
                }
            }
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }

        return arguments[valueIndex]
    }
}
#endif
