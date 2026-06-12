import Foundation

enum SlotDefaults {
    static let enabledSlotIDs = PhysicalKey.supportedDigits.map(\.digitValue)

    private static let sortOrderBySlotID = Dictionary(
        uniqueKeysWithValues: enabledSlotIDs.enumerated().map { index, slotID in
            (slotID, index)
        }
    )

    static func orderedSlotIDs(_ slotIDs: [Int]) -> [Int] {
        slotIDs.sorted { lhs, rhs in
            switch (sortOrderBySlotID[lhs], sortOrderBySlotID[rhs]) {
            case let (lhsOrder?, rhsOrder?):
                return lhsOrder < rhsOrder
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs < rhs
            }
        }
    }
}
