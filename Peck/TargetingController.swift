import AppKit
import Carbon.HIToolbox

/// Owns the arm → pick → click → type lifecycle.
final class TargetingController {

    private var overlays: [OverlayWindow] = []
    private var targetWindows: [CapturedTarget] = []
    private(set) var isArmed = false
    var onStateChange: ((Bool) -> Void)?

    func toggle() {
        isArmed ? disarm() : arm()
    }

    func arm() {
        guard !isArmed else { return }

        // Never overlap an in-flight paste: while typing, arming instead aborts,
        // matching the hotkey and status-item click. Overlapping would fire a second
        // focus-click mid-type and land the rest of the first paste on the new target.
        if Typist.shared.isTyping {
            Typist.shared.cancel()
            return
        }

        guard AccessibilityGate.check(prompt: true) else { return }

        guard !IsSecureEventInputEnabled() else {
            Typist.shared.recordFailure("Secure Input is active, so Peck cannot protect Escape. Nothing was typed. Close the app or field holding Secure Input, then retry.")
            return
        }

        targetWindows = TargetApplication.windows()
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
        let cgPoint = CoordinateConverter.toCG(screenPoint)
        let target = targetWindows.first { $0.bounds.contains(cgPoint) }
        disarm()
        guard let target else {
            Typist.shared.recordFailure("No target window could be identified. Nothing was typed.")
            return
        }
        submit(target: target, focusPoint: cgPoint)
    }

    /// The menu supplies the snapshot taken before menu tracking, not an app
    /// guessed after confirmation has activated Peck.
    func typeAtCurrentFocus(_ target: CapturedTarget?) {
        if isArmed { disarm(); return }
        guard !Typist.shared.isTyping else { Typist.shared.cancel(); return }
        guard AccessibilityGate.check(prompt: true), let target else {
            Typist.shared.recordFailure("Current focus could not be identified or Accessibility is unavailable. Nothing was typed.")
            return
        }
        submit(target: target, focusPoint: nil)
    }

    private func submit(target: CapturedTarget, focusPoint: CGPoint?) {
        guard !IsSecureEventInputEnabled() else {
            Typist.shared.recordFailure("Secure Input is active, so Peck cannot protect Escape. Nothing was typed. Close the app or field holding Secure Input, then retry.")
            return
        }
        let rawText = ClipboardTextReader.read() ?? ""

        // The guardrail against pecking a huge file into a root shell. Count what will
        // actually be typed — control characters that are silently dropped, and one
        // stripped trailing newline, don't count — so the figure can't be inflated (or
        // deflated) relative to the real payload.
        let prefs = Preferences.shared
        let typedCount = TextProcessing.typedCharacterCount(
            for: rawText, stripTrailingNewline: prefs.stripTrailingNewline)
        let plan = TextProcessing.typingPlan(for: rawText, workaround: prefs.indentWorkaround,
            stripTrailingNewline: prefs.stripTrailingNewline, appendReturn: prefs.pressReturnAfterTyping)
        guard !plan.isEmpty else { return }
        let returns = PasteSafety.returnCount(in: plan)
        if PasteSafety.shouldConfirm(typedCount: typedCount, returns: returns,
            confirmationEnabled: prefs.confirmBeforeTyping,
            warnOnReturn: prefs.warnOnReturn, threshold: prefs.largePasteThreshold) {
            if !confirmPaste(typedCount: typedCount, returns: returns) { return }
        }

        // The focus click and the pre-type settle now run inside Typist, on its serial
        // queue and under the cancellation generation, so `isTyping` is true (and Esc /
        // the hotkey / the icon abort the paste) for the entire pre-type window instead
        // of only once typing begins. Handing the point to Typist also means no second
        // synthetic click is posted from here that a re-armed overlay could catch.
        let settleDelay: TimeInterval = 0.15
        let preTypeDelay = TimeInterval(max(0, prefs.preTypeDelayMs)) / 1000.0
        Typist.shared.type(rawText, focusPoint: focusPoint,
                           settleDelay: settleDelay, preTypeDelay: preTypeDelay, target: target)
    }

    // MARK: - Confirmation alerts

    /// Make Cancel the keyboard default so a stray Return dismisses a guardrail
    /// safely instead of confirming the very action it exists to prevent.
    private func makeCancelDefault(_ alert: NSAlert) {
        // buttons[0] is the affirmative (added first), buttons[1] is Cancel.
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.dropFirst().first?.keyEquivalent = "\r"
    }

    private func confirmPaste(typedCount: Int, returns: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Type \(typedCount) characters and \(returns) Return presses?"
        alert.informativeText = "Return can execute commands in a console. This count includes remaining clipboard newlines and any appended Return. Clipboard contents are not displayed. In vi/Vim, :set paste alone does not enter Insert mode: enter Insert mode yourself before starting. Peck cannot detect the guest editor mode."
        alert.addButton(withTitle: "Type It")
        alert.addButton(withTitle: "Cancel")
        makeCancelDefault(alert)
        return runModalConfirmation(alert)
    }

    /// Bring the (accessory) app forward so the modal alert is visible, then run it.
    /// Returns true when the user chose the first (affirmative) button.
    private func runModalConfirmation(_ alert: NSAlert) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
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
        let source = SyntheticEventTag.makeSource()

        let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                           mouseCursorPosition: point, mouseButton: .left)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: .left)

        // A real single click carries click-state 1; CGEvent defaults to 0, and
        // some targets consult the count when routing focus.
        down?.setIntegerValueField(.mouseEventClickState, value: 1)
        up?.setIntegerValueField(.mouseEventClickState, value: 1)

        move?.post(tap: .cghidEventTap)
        usleep(20_000)
        down?.post(tap: .cghidEventTap)
        usleep(30_000)
        up?.post(tap: .cghidEventTap)
    }
}

enum ClipboardTextReader {
    /// Read the clipboard as the text Peck will type.
    ///
    /// The plain-text flavor is **always** preferred when it exists. That keeps what
    /// gets typed identical to what the user sees — no rich-vs-plain substitution that
    /// could quietly move where a console's Return-executed line breaks fall — and,
    /// crucially, it means the WebKit-backed `NSAttributedString` HTML importer is never
    /// run on untrusted clipboard data. That importer resolves external references
    /// (remote images/CSS) while parsing, so it can make Peck — an app whose whole
    /// posture is "no network" — silently beacon out to an attacker-controlled host from
    /// a single line copied off a web page, and it is a large untrusted-input parser
    /// surface with a CVE history.
    ///
    /// Only when there is no usable plain flavor at all does Peck fall back to RTF, whose
    /// `NSAttributedString` import is an offline parser (images are embedded, not
    /// fetched). HTML is deliberately not parsed here, so clipboard reading stays
    /// network-incapable by construction.
    static func read(from pasteboard: NSPasteboard = .general) -> String? {
        if let plain = pasteboard.string(forType: .string)
            .map(TextNormalizer.normalizedLineBreaks), !plain.isEmpty {
            return plain
        }

        if let rtf = attributedString(from: pasteboard, type: .rtf, documentType: .rtf)
            .map(TextNormalizer.normalizedLineBreaks), !rtf.isEmpty {
            return rtf
        }

        return nil
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

struct CapturedTarget {
    let identity: TargetIdentity
    let bounds: CGRect
}

/// Only process IDs, window IDs and geometry are read. No titles or contents.
/// Window identity is not a browser-tab identity or guest insertion-state check.
enum TargetApplication {
    static func windows() -> [CapturedTarget] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let id = window[kCGWindowNumber as String] as? UInt32 else { return nil }
            return CapturedTarget(identity: TargetIdentity(pid: pid, windowID: id), bounds: rect)
        }
    }
    static func current() -> CapturedTarget? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return windows().first { $0.identity.pid == pid }
    }
    static func matches(_ target: CapturedTarget) -> Bool {
        current()?.identity == target.identity
    }
    static func remainsAtPoint(_ target: CapturedTarget, point: CGPoint) -> Bool {
        windows().first { $0.bounds.contains(point) }?.identity == target.identity
    }
}
