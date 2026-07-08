import AppKit

/// Transparent full-screen window (one per display) that captures a single
/// click while targeting is armed. Esc cancels.
final class OverlayWindow: NSWindow {

    var onPick: ((NSPoint) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        hasShadow = false
        backgroundColor = NSColor.black.withAlphaComponent(0.12)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = OverlayView()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let screenPoint = convertPoint(toScreen: event.locationInWindow)
        onPick?(screenPoint)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        }
        // Swallow everything else; no beeps while armed.
    }
}

final class OverlayView: NSView {

    private var mouseLocation: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Crosshair guide lines following the cursor.
        if let loc = mouseLocation {
            let lineColor = NSColor.white.withAlphaComponent(0.55)
            lineColor.setStroke()

            let vertical = NSBezierPath()
            vertical.move(to: NSPoint(x: loc.x, y: bounds.minY))
            vertical.line(to: NSPoint(x: loc.x, y: bounds.maxY))
            vertical.lineWidth = 1
            vertical.stroke()

            let horizontal = NSBezierPath()
            horizontal.move(to: NSPoint(x: bounds.minX, y: loc.y))
            horizontal.line(to: NSPoint(x: bounds.maxX, y: loc.y))
            horizontal.lineWidth = 1
            horizontal.stroke()
        }

        // Hint banner near the top of the screen.
        let hint = "Click where you want your clipboard typed  •  Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let hintString = NSAttributedString(string: hint, attributes: attributes)
        let textSize = hintString.size()

        let padding: CGFloat = 14
        let pillRect = NSRect(
            x: bounds.midX - textSize.width / 2 - padding,
            y: bounds.maxY - 90,
            width: textSize.width + padding * 2,
            height: textSize.height + padding)

        let pill = NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2)
        NSColor.black.withAlphaComponent(0.65).setFill()
        pill.fill()

        hintString.draw(at: NSPoint(
            x: pillRect.midX - textSize.width / 2,
            y: pillRect.midY - textSize.height / 2))
    }
}
