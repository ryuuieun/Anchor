enum WindowSlotMenuModel {
    static func sortedSlots(_ slots: [WindowSlot]) -> [WindowSlot] {
        let orderedSlotIDs = SlotDefaults.orderedSlotIDs(slots.map(\.id))
        let slotByID = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0) })
        return orderedSlotIDs.compactMap { slotByID[$0] }
    }

    static func bindableSlots(from slots: [WindowSlot]) -> [WindowSlot] {
        sortedSlots(slots).filter { $0.window == nil }
    }
}
