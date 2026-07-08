import AppKit

/// Owns the arm → pick → click → type lifecycle.
final class TargetingController {

    private var overlays: [OverlayWindow] = []
    private(set) var isArmed = false
    var onStateChange: ((Bool) -> Void)?

    func toggle() {
        isArmed ? disarm() : arm()
    }

    func arm() {
        guard !isArmed else { return }
        guard AccessibilityGate.check(prompt: true) else { return }

        isArmed = true

        for screen in NSScreen.screens {
            let overlay = OverlayWindow(screen: screen)
            overlay.onPick = { [weak self] screenPoint in
                self?.picked(at: screenPoint)
            }
            overlay.onCancel = { [weak self] in
                self?.disarm()
            }
            overlay.orderFrontRegardless()
            overlays.append(overlay)
        }

        NSApp.activate(ignoringOtherApps: true)
        overlays.first?.makeKeyAndOrderFront(nil)
        onStateChange?(true)
    }

    func disarm() {
        guard isArmed else { return }
        isArmed = false
        tearDownOverlays()
        onStateChange?(false)
    }

    /// Fully dismantle every overlay. Severing the callbacks and disabling mouse
    /// events matters: the synthetic click posted from `picked` lands ~150 ms
    /// later, and a still-composited overlay must neither swallow that click nor
    /// re-fire `onPick` (which would re-read the clipboard and paste a second
    /// time — a real hazard when the clipboard is a password).
    private func tearDownOverlays() {
        for overlay in overlays {
            overlay.onPick = nil
            overlay.onCancel = nil
            overlay.ignoresMouseEvents = true
            overlay.orderOut(nil)
            overlay.close()
        }
        overlays.removeAll()
    }

    private func picked(at screenPoint: NSPoint) {
        // Re-entrancy guard: only the first pick of a session is honored. A stray
        // synthetic click that hit-tests a lingering overlay arrives with the
        // session already disarmed and must not schedule a second click+type.
        guard isArmed else { return }
        disarm()

        let cgPoint = CoordinateConverter.toCG(screenPoint)
        let text = ClipboardTextReader.read() ?? ""
        let preTypeDelay = Double(max(0, Preferences.shared.preTypeDelayMs)) / 1000.0

        DispatchQueue.global(qos: .userInitiated).async {
            // The overlays are already closed and set to ignore mouse events, so
            // correctness no longer hinges on this settle — it just gives the
            // window server a beat to route focus to the real target underneath.
            Thread.sleep(forTimeInterval: 0.15)

            MouseClicker.click(at: cgPoint)

            guard !text.isEmpty else { return }
            Thread.sleep(forTimeInterval: preTypeDelay)
            Typist.shared.type(text)
        }
    }
}

/// AppKit screen coordinates are bottom-left origin; CGEvent wants
/// top-left origin of the primary display. Flip Y accordingly. The pure math
/// lives in `CoordinateMath` so it can be unit-tested without a live NSScreen.
enum CoordinateConverter {
    static func toCG(_ point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CoordinateMath.toCG(point, primaryHeight: primaryHeight)
    }
}

enum MouseClicker {
    static func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .combinedSessionState)

        let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                           mouseCursorPosition: point, mouseButton: .left)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: .left)

        move?.post(tap: .cghidEventTap)
        usleep(20_000)
        down?.post(tap: .cghidEventTap)
        usleep(30_000)
        up?.post(tap: .cghidEventTap)
    }
}

enum ClipboardTextReader {
    private struct Candidate {
        let text: String
        let priority: Int

        var lineBreakCount: Int {
            TextNormalizer.lineBreakCount(in: text)
        }
    }

    static func read(from pasteboard: NSPasteboard = .general) -> String? {
        let plainText = pasteboard.string(forType: .string)
            .map(TextNormalizer.normalizedLineBreaks)
            .flatMap { $0.isEmpty ? nil : $0 }

        if let plainText, TextNormalizer.lineBreakCount(in: plainText) > 0 {
            return plainText
        }

        var richCandidates: [Candidate] = []

        if let html = attributedString(from: pasteboard, type: .html, documentType: .html) {
            richCandidates.append(Candidate(text: html, priority: 20))
        }

        if let rtf = attributedString(from: pasteboard, type: .rtf, documentType: .rtf) {
            richCandidates.append(Candidate(text: rtf, priority: 10))
        }

        let normalizedRich = richCandidates
            .map { Candidate(text: TextNormalizer.normalizedLineBreaks($0.text), priority: $0.priority) }
            .filter { !$0.text.isEmpty }

        // When plain text exists but is single-line, only prefer a rich flavor that
        // actually recovers line structure the plain flavor lost.
        let multiLineRich = normalizedRich
            .filter { $0.lineBreakCount > 0 }
            .max(by: Self.ranks)?
            .text

        if let plainText, let multiLineRich {
            return TextNormalizer.sameWords(plainText, multiLineRich) ? multiLineRich : plainText
        }

        if let plainText {
            return plainText
        }

        // No usable plain flavor at all: fall back to the best rich candidate even
        // if it is single-line, so a rich-only clipboard still types something.
        return normalizedRich.max(by: Self.ranks)?.text
    }

    /// Orders candidates worst-to-best: more recovered line breaks wins, ties broken
    /// by source priority (HTML over RTF).
    private static func ranks(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.lineBreakCount != rhs.lineBreakCount {
            return lhs.lineBreakCount < rhs.lineBreakCount
        }
        return lhs.priority < rhs.priority
    }

    private static func attributedString(
        from pasteboard: NSPasteboard,
        type: NSPasteboard.PasteboardType,
        documentType: NSAttributedString.DocumentType
    ) -> String? {
        guard let data = pasteboard.data(forType: type) else { return nil }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: documentType
        ]

        return try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ).string
    }
}
