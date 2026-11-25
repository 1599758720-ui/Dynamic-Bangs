@main
struct TestInteractionState {
    static func main() {
        var deliberateOpen = ExpandedInteraction(awaitingPointerEntry: true)

        // Double-click opens from the menu bar, so mouse-up is outside.
        precondition(!deliberateOpen.updatePointer(inside: false, heldOpen: false))
        precondition(!deliberateOpen.updatePointer(inside: false, heldOpen: false))
        precondition(deliberateOpen.dismissesOnClick(inside: false, pinned: false, editing: false))
        precondition(!deliberateOpen.dismissesOnClick(inside: true, pinned: false, editing: false))
        precondition(!deliberateOpen.dismissesOnClick(inside: false, pinned: true, editing: false))
        precondition(!deliberateOpen.dismissesOnClick(inside: false, pinned: false, editing: true))

        precondition(!deliberateOpen.updatePointer(inside: true, heldOpen: false))
        precondition(deliberateOpen.updatePointer(inside: false, heldOpen: false))
        precondition(!deliberateOpen.updatePointer(inside: false, heldOpen: true))
        precondition(!deliberateOpen.updatePointer(inside: true, heldOpen: true))

        var fileDrop = ExpandedInteraction()
        precondition(fileDrop.updatePointer(inside: false, heldOpen: false))
        print("Interaction state tests passed")
    }
}
