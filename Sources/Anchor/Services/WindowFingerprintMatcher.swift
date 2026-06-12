import CoreGraphics
import Foundation

enum WindowFingerprintMatchResult: Equatable {
    case match(Int)
    case missing
    case ambiguous(String)
}

enum WindowFingerprintMatchConfidence {
    case strongIdentity
    case titleAndGeometry
}

struct WindowFingerprintMatcher {
    static func match(
        original: WindowFingerprint,
        candidates: [WindowFingerprint],
        minimumConfidence: WindowFingerprintMatchConfidence = .titleAndGeometry
    ) -> WindowFingerprintMatchResult {
        let compatibleCandidates = candidates.enumerated().filter { _, candidate in
            attributesCompatible(candidate, with: original)
        }

        if let identifier = original.identifier, !identifier.isEmpty {
            let identifierMatches = compatibleCandidates.filter { _, candidate in
                candidate.identifier == identifier
            }
            if let match = uniqueMatch(identifierMatches) {
                return .match(match.offset)
            }
            if identifierMatches.count > 1 {
                return .ambiguous("window identity ambiguous")
            }
        }

        if let cgWindowID = original.cgWindowID {
            let cgWindowMatches = compatibleCandidates.filter { _, candidate in
                candidate.cgWindowID == cgWindowID
            }
            if let match = uniqueMatch(cgWindowMatches) {
                return .match(match.offset)
            }
            if cgWindowMatches.count > 1 {
                return .ambiguous("window identity ambiguous")
            }
        }

        guard minimumConfidence == .titleAndGeometry else {
            return .missing
        }

        let geometryCandidates = compatibleCandidates.filter { _, candidate in
            candidate.title == original.title && geometryFingerprintsMatch(candidate, original)
        }
        if let match = uniqueMatch(geometryCandidates) {
            return .match(match.offset)
        }
        if geometryCandidates.count > 1 {
            return .ambiguous("window identity ambiguous")
        }

        let titleOnlyMatches = compatibleCandidates.filter { _, candidate in
            candidate.title == original.title
        }
        return titleOnlyMatches.isEmpty ? .missing : .ambiguous("window identity ambiguous")
    }

    private static func uniqueMatch(
        _ matches: [(offset: Int, element: WindowFingerprint)]
    ) -> (offset: Int, element: WindowFingerprint)? {
        matches.count == 1 ? matches[0] : nil
    }

    private static func attributesCompatible(
        _ candidate: WindowFingerprint,
        with original: WindowFingerprint
    ) -> Bool {
        guard candidate.pid == original.pid,
              candidate.bundleIdentifier == original.bundleIdentifier,
              candidate.role == original.role else {
            return false
        }

        if let originalSubrole = original.subrole {
            return candidate.subrole == originalSubrole
        }
        return true
    }

    private static func geometryFingerprintsMatch(
        _ candidate: WindowFingerprint,
        _ original: WindowFingerprint
    ) -> Bool {
        guard let candidatePosition = candidate.position,
              let originalPosition = original.position,
              let candidateSize = candidate.size,
              let originalSize = original.size else {
            return false
        }

        let tolerance: CGFloat = 8
        return abs(candidatePosition.x - originalPosition.x) <= tolerance
            && abs(candidatePosition.y - originalPosition.y) <= tolerance
            && abs(candidateSize.width - originalSize.width) <= tolerance
            && abs(candidateSize.height - originalSize.height) <= tolerance
    }
}
