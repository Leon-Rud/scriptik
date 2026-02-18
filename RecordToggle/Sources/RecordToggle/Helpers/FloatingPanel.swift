import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
    }

    // Override to prevent becoming key/main window
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Helper to show with SwiftUI content
    func show<Content: View>(@ViewBuilder content: () -> Content) {
        let hostingView = NSHostingView(rootView: content())
        hostingView.frame = contentRect(forFrameRect: frame)
        contentView = hostingView
        orderFrontRegardless()
    }
}
