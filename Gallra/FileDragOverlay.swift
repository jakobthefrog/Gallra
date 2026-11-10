import AppKit
import SwiftUI

/// Transparent layer over a thumbnail that handles left-click and drag.
/// A drag carries the real files (copy only, so Finder/Desktop make copies and the originals stay put)
/// plus the paths as text, which the grid uses to move photos between groups.
struct FileDragOverlay: NSViewRepresentable {
    /// Files to drag, evaluated when the drag starts.
    let urls: () -> [URL]
    /// Click with its click count and modifier keys.
    let onClick: (Int, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) {
        view.urls = urls
        view.onClick = onClick
    }

    final class DragView: NSView, NSDraggingSource {
        var urls: () -> [URL] = { [] }
        var onClick: (Int, NSEvent.ModifierFlags) -> Void = { _, _ in }
        private var downEvent: NSEvent?
        private var dragged = false

        /// Only left-button events are ours; right-click (context menu), scrolling and hover pass through.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type),
                  !event.modifierFlags.contains(.control) else { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) { downEvent = event; dragged = false }

        override func mouseUp(with event: NSEvent) {
            defer { downEvent = nil }
            guard !dragged else { return }
            onClick(event.clickCount, event.modifierFlags)
        }

        override func mouseDragged(with event: NSEvent) {
            guard !dragged, let start = downEvent else { return }
            let a = start.locationInWindow, b = event.locationInWindow
            guard hypot(b.x - a.x, b.y - a.y) > 4 else { return }
            let files = urls()
            guard !files.isEmpty else { return }
            dragged = true
            let image = snapshot()
            let items = files.enumerated().map { index, url -> NSDraggingItem in
                let writer: NSPasteboardWriting
                if index == 0 {
                    // First item also carries the paths as text for in-app grouping.
                    let item = NSPasteboardItem()
                    item.setString(url.absoluteString, forType: .fileURL)
                    item.setString(files.map(\.path).joined(separator: "\n"), forType: .string)
                    writer = item
                } else {
                    writer = url as NSURL
                }
                let dragItem = NSDraggingItem(pasteboardWriter: writer)
                dragItem.setDraggingFrame(bounds, contents: image)
                return dragItem
            }
            beginDraggingSession(with: items, event: start, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        /// A picture of the thumbnail under the cursor, or the file icon if it can't be captured.
        private func snapshot() -> NSImage {
            if let host = window?.contentView {
                let rect = convert(bounds, to: host)
                if let rep = host.bitmapImageRepForCachingDisplay(in: rect) {
                    host.cacheDisplay(in: rect, to: rep)
                    let image = NSImage(size: bounds.size)
                    image.addRepresentation(rep)
                    return image
                }
            }
            return NSWorkspace.shared.icon(for: .data)
        }
    }
}
