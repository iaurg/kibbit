import AppKit

/// Spotlight-style floating panel. Unlike NSPopover it shows over fullscreen apps and, being
/// non-activating, takes keystrokes without stealing app focus from the terminal/editor.
final class PetPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init(contentView view: NSView, size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        // Clicking anywhere else dismisses it.
        if isVisible { onDismiss?() }
    }

    /// Top of the given screen, under the status item when it lives on that screen.
    func place(anchor: NSRect?, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let x: CGFloat
        if let anchor, visible.minX...visible.maxX ~= anchor.midX {
            x = anchor.midX - frame.width / 2
        } else {
            x = visible.maxX - frame.width - 12
        }
        let clampedX = min(max(x, visible.minX + 8), visible.maxX - frame.width - 8)
        setFrameOrigin(NSPoint(x: clampedX, y: visible.maxY - frame.height - 6))
    }
}
