import Foundation

enum ModifierDoubleTapKey: Equatable {
    case leftOption
    case rightOption
}

struct ModifierDoubleTapConfiguration: Equatable {
    let maximumTapDuration: TimeInterval
    let maximumIntervalBetweenTaps: TimeInterval
    let triggerCooldown: TimeInterval

    static let optionBindingDefault = ModifierDoubleTapConfiguration(
        maximumTapDuration: 0.25,
        maximumIntervalBetweenTaps: 0.35,
        triggerCooldown: 0.5
    )
}

enum ModifierDoubleTapEvent: Equatable {
    case optionChanged(
        key: ModifierDoubleTapKey,
        isDown: Bool,
        hasDisallowedModifiers: Bool,
        timestamp: TimeInterval
    )
    case cancel(timestamp: TimeInterval)
}

struct ModifierDoubleTapRecognizer {
    private enum Phase: Equatable {
        case idle
        case firstDown(key: ModifierDoubleTapKey, downTime: TimeInterval)
        case waitingSecondTap(key: ModifierDoubleTapKey, firstUpTime: TimeInterval)
        case secondDown(
            key: ModifierDoubleTapKey,
            firstUpTime: TimeInterval,
            downTime: TimeInterval
        )
    }

    private let configuration: ModifierDoubleTapConfiguration
    private var phase: Phase = .idle
    private var suppressTriggersUntil: TimeInterval = 0

    init(configuration: ModifierDoubleTapConfiguration = .optionBindingDefault) {
        self.configuration = configuration
    }

    mutating func handle(_ event: ModifierDoubleTapEvent) -> Bool {
        switch event {
        case .cancel:
            phase = .idle
            return false

        case .optionChanged(let key, let isDown, let hasDisallowedModifiers, let timestamp):
            guard timestamp >= suppressTriggersUntil else {
                phase = .idle
                return false
            }

            guard !hasDisallowedModifiers else {
                phase = .idle
                return false
            }

            return handleOptionChange(key: key, isDown: isDown, timestamp: timestamp)
        }
    }

    private mutating func handleOptionChange(
        key: ModifierDoubleTapKey,
        isDown: Bool,
        timestamp: TimeInterval
    ) -> Bool {
        switch phase {
        case .idle:
            if isDown {
                phase = .firstDown(key: key, downTime: timestamp)
            }
            return false

        case .firstDown(let activeKey, let downTime):
            guard key == activeKey else {
                phase = .idle
                return false
            }

            guard !isDown else {
                return false
            }

            if timestamp - downTime <= configuration.maximumTapDuration {
                phase = .waitingSecondTap(key: key, firstUpTime: timestamp)
            } else {
                phase = .idle
            }
            return false

        case .waitingSecondTap(let activeKey, let firstUpTime):
            guard isDown else {
                phase = .idle
                return false
            }

            guard timestamp - firstUpTime <= configuration.maximumIntervalBetweenTaps else {
                phase = .firstDown(key: key, downTime: timestamp)
                return false
            }

            guard key == activeKey else {
                phase = .idle
                return false
            }

            phase = .secondDown(key: key, firstUpTime: firstUpTime, downTime: timestamp)
            return false

        case .secondDown(let activeKey, let firstUpTime, let downTime):
            guard key == activeKey else {
                phase = .idle
                return false
            }

            guard !isDown else {
                return false
            }

            let isTapShortEnough = timestamp - downTime <= configuration.maximumTapDuration
            let isSecondTapSoonEnough = downTime - firstUpTime <= configuration.maximumIntervalBetweenTaps
            phase = .idle

            guard isTapShortEnough && isSecondTapSoonEnough else {
                return false
            }

            suppressTriggersUntil = timestamp + configuration.triggerCooldown
            return true
        }
    }
}
