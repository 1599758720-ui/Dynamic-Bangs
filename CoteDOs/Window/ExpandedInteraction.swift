struct ExpandedInteraction {
    var awaitingPointerEntry = false

    /// Deliberate opens wait for the pointer to reach the workbench before
    /// pointer exit can dismiss it. File drops use ordinary hover behavior.
    mutating func updatePointer(inside: Bool, heldOpen: Bool) -> Bool {
        if inside { awaitingPointerEntry = false }
        return !inside && !heldOpen && !awaitingPointerEntry
    }

    func dismissesOnClick(inside: Bool, pinned: Bool, editing: Bool) -> Bool {
        !inside && !pinned && !editing
    }
}
