import AppKit

/// The host window has room for shadows and expansion. Only the island and
/// the controller's file-drop region accept input.
final class NotchContainerView: NSView {
    var islandRect: () -> NSRect = { .zero }
    var dropRect: () -> NSRect = { .zero }
    var onDragEntered: (() -> Bool)?
    var onDragExited: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    private var acceptsDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard islandRect().contains(local) else { return nil }
        return super.hitTest(point) ?? self
    }

    // MARK: Drag destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropTarget(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropTarget(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearDropTarget()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        clearDropTarget()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptsDrag && containsDropLocation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { clearDropTarget() }
        guard acceptsDrag, containsDropLocation(sender) else { return false }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func updateDropTarget(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSourceOperationMask.contains(.copy), containsDropLocation(sender) else {
            clearDropTarget()
            return []
        }
        if !acceptsDrag { acceptsDrag = onDragEntered?() ?? false }
        return acceptsDrag ? .copy : []
    }

    private func containsDropLocation(_ sender: NSDraggingInfo) -> Bool {
        dropRect().contains(convert(sender.draggingLocation, from: nil))
    }

    private func clearDropTarget() {
        guard acceptsDrag else { return }
        acceptsDrag = false
        onDragExited?()
    }
}
