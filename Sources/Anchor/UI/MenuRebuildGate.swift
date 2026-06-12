struct MenuRebuildGate {
    private var isMenuOpen = false
    private var needsRebuildAfterClose = false

    mutating func menuWillOpen() {
        isMenuOpen = true
    }

    mutating func requestRebuild() -> Bool {
        guard isMenuOpen else {
            return true
        }

        needsRebuildAfterClose = true
        return false
    }

    mutating func menuDidClose() -> Bool {
        isMenuOpen = false
        let shouldRebuild = needsRebuildAfterClose
        needsRebuildAfterClose = false
        return shouldRebuild
    }
}
