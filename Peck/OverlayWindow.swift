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
        // Only a real human click picks a target. Ignore synthetic clicks — e.g. Peck's
        // own focus click — so that even if a session somehow re-arms while a prior
        // pick's focus click is still in flight, that click can't be mistaken for a
        // second pick (which would read the clipboard and paste again).
        guard !SyntheticEventTag.isSynthetic(event) else { return }
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

    // The hint banner is constant for the whole targeting session, so build its
    // attributed string and measure it once rather than re-allocating and re-laying it
    // out on every mouse-move repaint.
    private static let hintText = "Click where you want your clipboard typed  •  Esc to cancel"
    private let hintString: NSAttributedString = {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        return NSAttributedString(string: OverlayView.hintText, attributes: attributes)
    }()
    private lazy var hintSize: NSSize = hintString.size()

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
        let newLocation = convert(event.locationInWindow, from: nil)
        let previous = mouseLocation
        mouseLocation = newLocation
        // Repaint only the crosshair strips — the old position (to erase the old lines)
        // and the new one (to draw them) — instead of invalidating the whole display on
        // every event. Full-screen redraws at ProMotion rates were the real cost here;
        // the static hint pill stays in the backing store between moves.
        if let previous { invalidateCrosshair(at: previous) }
        invalidateCrosshair(at: newLocation)
    }

    /// Invalidate the two thin strips the crosshair through `point` occupies — a full-height
    /// vertical column and a full-width horizontal row — as **separate** rects. Unioning
    /// them would produce the whole-view bounding box (a full-height column ∪ a full-width
    /// row encloses everything), defeating the scoping; keeping them separate leaves the
    /// dirty region a thin cross that draw()'s clip actually limits the compositing to.
    private func invalidateCrosshair(at point: NSPoint) {
        setNeedsDisplay(NSRect(x: point.x - 1, y: bounds.minY, width: 3, height: bounds.height))
        setNeedsDisplay(NSRect(x: bounds.minX, y: point.y - 1, width: bounds.width, height: 3))
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

        // Hint banner near the top of the screen (string and measurement cached).
        let textSize = hintSize
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
