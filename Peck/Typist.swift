import AppKit
import Carbon.HIToolbox

/// Every synthetic event Peck posts is stamped with a magic
/// `kCGEventSourceUserData` value so Peck can recognize its own events when they
/// come back around through the window server. `KeyMonitor` relies on this: the
/// bracketed-paste markers contain a synthetic Escape (keycode 53), and without
/// the tag the Esc-to-abort monitor would cancel the very paste that posted it.
///
/// The tag is a self-identification mechanism, not a trust boundary: the value
/// is public and any process that can post events could forge it. Never use
/// `isSynthetic` as a security signal — here a forged tag can only make Peck
/// ignore an Esc it would otherwise ignore anyway, and an untagged forged Esc
/// merely aborts typing, which is the fail-safe direction.
enum SyntheticEventTag {
    /// 'PECK' — copied from the source into every event it creates.
    static let magic: Int64 = 0x5045_434B

    static func makeSource() -> CGEventSource? {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            // Events created against a nil source fall back to an untagged
            // default source, which would resurrect the self-abort bug — make
            // the (unlikely) failure visible instead of silent.
            NSLog("Peck: CGEventSource creation failed; synthetic events will be untagged")
            return nil
        }
        source.userData = magic
        return source
    }

    static func isSynthetic(_ event: NSEvent) -> Bool {
        guard let cgEvent = event.cgEvent else { return false }
        return cgEvent.getIntegerValueField(.eventSourceUserData) == magic
    }
}

/// Turns clipboard text into synthetic keystrokes.
///
/// Two engines:
///  - **Keycodes** (default): resolves each character to a real virtual
///    keycode + modifiers from the active keyboard layout and presses the
///    actual keys, including physical Shift/Option press-and-release. This is
///    what noVNC, vSphere web consoles, and RDP want, because they key off
///    hardware keycodes rather than injected text.
///  - **Unicode**: injects characters directly via
///    `keyboardSetUnicodeString`. Handles any character in any script, but
///    some VNC-style consoles ignore or mangle it.
///
/// Characters the keycode engine can't map (emoji, characters outside the
/// current layout) automatically fall back to unicode injection.
final class Typist {

    static let shared = Typist()
    private init() {}

    /// Fired on the main thread when typing starts (`true`) and when it ends
    /// (`false`) — whether it finished or was aborted. Drives the menu-bar
    /// "typing" icon and the Esc/hotkey abort monitor.
    var onTypingStateChange: ((Bool) -> Void)?

    /// Typing runs on its own serial queue so it never blocks the main thread and
    /// so an in-flight job can be cancelled cleanly.
    private let queue = DispatchQueue(label: "dev.homelab.peck.typist", qos: .userInitiated)
    private let lock = NSLock()
    // Each `type()` gets a monotonically increasing generation. `cancel()` records
    // the newest generation issued so far as cancelled, so a run only aborts for a
    // cancel that targets it (or a later one) — a second paste can never reset the
    // flag out from under a pending abort, and a stale cancel can't kill a new run.
    private var _generation = 0
    private var _cancelledThrough = 0
    private var _isTyping = false

    /// Whether a typing job is currently running. Used to route the global hotkey
    /// to "abort" instead of "arm" while typing.
    var isTyping: Bool { lock.withLock { _isTyping } }

    /// Enqueue clipboard text to be typed. Returns immediately; the optional focus
    /// click, the pre-type settle, and the typing all proceed on the dedicated queue
    /// and can be stopped with `cancel()`.
    ///
    /// `isTyping` is set **synchronously** here, before returning, so the entire
    /// pre-type window (focus click + `settleDelay` + `preTypeDelay`) is covered: an
    /// abort gesture during it routes to `cancel()` and `arm()` aborts instead of
    /// overlapping. Previously `isTyping` only flipped once the background job reached
    /// the typing loop, leaving a dead window where the paste was already committed but
    /// uncancellable, and where the hotkey re-armed a fresh session (whose overlay could
    /// then catch the pending synthetic focus click and paste a second time).
    func type(_ rawText: String,
              focusPoint: CGPoint? = nil,
              settleDelay: TimeInterval = 0,
              preTypeDelay: TimeInterval = 0) {
        let prefs = Preferences.shared
        let plan = TextProcessing.typingPlan(
            for: rawText,
            workaround: prefs.indentWorkaround,
            stripTrailingNewline: prefs.stripTrailingNewline,
            appendReturn: prefs.pressReturnAfterTyping)

        // Nothing to type → never engage typing state or post a focus click.
        guard !plan.isEmpty else { return }

        let generation = lock.withLock { () -> Int in
            _generation += 1
            return _generation
        }
        setTyping(true)

        let keystrokeDelayMs = prefs.keystrokeDelayMs
        let workaround = prefs.indentWorkaround
        queue.async { [weak self] in
            self?.run(plan: plan, generation: generation, keystrokeDelayMs: keystrokeDelayMs,
                      workaround: workaround, focusPoint: focusPoint,
                      settleDelay: settleDelay, preTypeDelay: preTypeDelay)
        }
    }

    /// Request that in-progress (and already-queued) typing stop as soon as
    /// possible. Thread-safe.
    func cancel() {
        lock.withLock { _cancelledThrough = _generation }
    }

    private func isCancelled(_ generation: Int) -> Bool {
        lock.withLock { _cancelledThrough >= generation }
    }

    private func run(plan: [TypingInstruction], generation: Int, keystrokeDelayMs: Int,
                     workaround: IndentWorkaround, focusPoint: CGPoint?,
                     settleDelay: TimeInterval, preTypeDelay: TimeInterval) {
        // Balances the synchronous setTyping(true) in type(); fires whether this run
        // finishes, is aborted, or bails during the pre-type window.
        defer { setTyping(false) }

        let source = SyntheticEventTag.makeSource()
        let delayMicroseconds = UInt32(max(0, keystrokeDelayMs)) * 1_000
        let mapper = makeMapperIfNeeded()

        // Focus the target, then let it settle — inside the cancellable window, so Esc /
        // the hotkey / the icon can still stop the paste before the first keystroke and
        // no click is posted at all if the user aborts during the settle.
        if let focusPoint {
            if sleepUnlessCancelled(settleDelay, generation: generation) { return }
            MouseClicker.click(at: focusPoint)
            if sleepUnlessCancelled(preTypeDelay, generation: generation) { return }
        }

        // In bracketed-paste mode, once the opening ESC[200~ has been posted the target
        // is in paste-receiving mode; if we abort we must still send the closing ESC[201~
        // or it stays stuck buffering everything the user types next. But only until the
        // plan's *own* closing marker has been posted — after that the target is already
        // out of paste mode, so an abort in the trailing-Return window (with "press Return
        // after typing" on) must not emit a second, stray ESC[201~.
        let bracketed = workaround == .bracketedPaste
        let openMarkerEnd = TextProcessing.bracketedPasteMarkerLength - 1
        // The close marker ends at the last instruction, unless an appended trailing Return
        // (the only way a bracketed plan ends in .returnKey — the marker ends in "~") sits
        // after it.
        var trailingReturn = false
        if let last = plan.last, last == .key(.returnKey) { trailingReturn = true }
        let closeMarkerEnd = bracketed ? plan.count - 1 - (trailingReturn ? 1 : 0) : -1
        var needsCloseOnAbort = false

        for (index, instruction) in plan.enumerated() {
            if isCancelled(generation) {
                if needsCloseOnAbort {
                    emitBracketedPasteClose(source: source, mapper: mapper)
                }
                // A character was typed atomically (press() balances its own
                // modifiers), so nothing should be held — but release defensively
                // so an aborted shifted/optioned keystroke can never strand a
                // modifier physically down.
                releaseModifiers(source: source)
                break
            }
            autoreleasepool {
                execute(instruction, source: source, mapper: mapper)
            }
            if bracketed {
                if index == openMarkerEnd { needsCloseOnAbort = true }
                if index == closeMarkerEnd { needsCloseOnAbort = false }
            }
            if delayMicroseconds > 0 {
                usleep(delayMicroseconds)
            }
        }
    }

    /// Sleep up to `seconds`, waking early (and returning true) if the run is cancelled,
    /// so even a long pre-type delay stays promptly abortable. Returns the cancellation
    /// state at the end.
    private func sleepUnlessCancelled(_ seconds: TimeInterval, generation: Int) -> Bool {
        guard seconds > 0 else { return isCancelled(generation) }
        let step: TimeInterval = 0.02
        var remaining = seconds
        while remaining > 0 {
            if isCancelled(generation) { return true }
            let chunk = min(step, remaining)
            Thread.sleep(forTimeInterval: chunk)
            remaining -= chunk
        }
        return isCancelled(generation)
    }

    /// Post the closing bracketed-paste marker (ESC[201~) to release a target left in
    /// paste-receiving mode by an aborted bracketed run.
    private func emitBracketedPasteClose(source: CGEventSource?, mapper: KeyMapper?) {
        for instruction in TextProcessing.bracketedPasteMarker(open: false) {
            execute(instruction, source: source, mapper: mapper)
        }
    }

    private func execute(_ instruction: TypingInstruction, source: CGEventSource?, mapper: KeyMapper?) {
        switch instruction {
        case .key(let key):
            emit(key, source: source, mapper: mapper)
        case .escape:
            press(keyCode: CGKeyCode(kVK_Escape), flags: [], source: source)
        case .selectLineStart:
            selectLineStart(source: source)
        }
    }

    /// Shift+Cmd+Left — select from the cursor back to the start of the line, so the
    /// next characters typed replace an editor's auto-indent whitespace.
    private func selectLineStart(source: CGEventSource?) {
        let flags: CGEventFlags = [.maskShift, .maskCommand]
        postKey(CGKeyCode(kVK_Command), down: true, flags: flags, source: source)
        postKey(CGKeyCode(kVK_Shift), down: true, flags: flags, source: source)
        postKey(CGKeyCode(kVK_LeftArrow), down: true, flags: flags, source: source)
        postKey(CGKeyCode(kVK_LeftArrow), down: false, flags: flags, source: source)
        postKey(CGKeyCode(kVK_Shift), down: false, flags: [], source: source)
        postKey(CGKeyCode(kVK_Command), down: false, flags: [], source: source)
    }

    private func setTyping(_ typing: Bool) {
        lock.withLock { _isTyping = typing }
        DispatchQueue.main.async { [weak self] in
            self?.onTypingStateChange?(typing)
        }
    }

    private func makeMapperIfNeeded() -> KeyMapper? {
        guard Preferences.shared.typingMode == .keycodes else { return nil }

        if Thread.isMainThread {
            return KeyMapper()
        }

        return DispatchQueue.main.sync {
            KeyMapper()
        }
    }

    // MARK: - Per-key dispatch

    private func emit(_ key: TypedKey, source: CGEventSource?, mapper: KeyMapper?) {
        switch key {
        case .returnKey:
            press(keyCode: CGKeyCode(kVK_Return), flags: [], source: source)
        case .tab:
            press(keyCode: CGKeyCode(kVK_Tab), flags: [], source: source)
        case .literal(let literal):
            if let mapper, let stroke = mapper.stroke(for: literal) {
                press(keyCode: stroke.keyCode, flags: stroke.flags, source: source)
            } else {
                injectUnicode(literal, source: source)
            }
        }
    }

    // MARK: - Keycode engine

    private func press(keyCode: CGKeyCode, flags: CGEventFlags, source: CGEventSource?) {
        // Physically press modifiers first. VNC-style consoles track modifier
        // state from real key events, not just event flags.
        if flags.contains(.maskShift) {
            postKey(CGKeyCode(kVK_Shift), down: true, flags: flags, source: source)
        }
        if flags.contains(.maskAlternate) {
            postKey(CGKeyCode(kVK_Option), down: true, flags: flags, source: source)
        }

        postKey(keyCode, down: true, flags: flags, source: source)
        postKey(keyCode, down: false, flags: flags, source: source)

        if flags.contains(.maskAlternate) {
            postKey(CGKeyCode(kVK_Option), down: false, flags: [], source: source)
        }
        if flags.contains(.maskShift) {
            postKey(CGKeyCode(kVK_Shift), down: false, flags: [], source: source)
        }
    }

    private func postKey(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags, source: CGEventSource?) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Unicode engine

    private func injectUnicode(_ character: Character, source: CGEventSource?) {
        let units = Array(String(character).utf16)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }

        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Abort safety

    /// Post key-up for every modifier we might synthesize, so aborting mid-stroke
    /// can never leave Shift/Option/Command/Control stuck down. A key-up for a key
    /// that isn't down is a harmless no-op.
    private func releaseModifiers(source: CGEventSource?) {
        let modifiers = [
            kVK_Shift, kVK_RightShift,
            kVK_Option, kVK_RightOption,
            kVK_Command, kVK_RightCommand,
            kVK_Control, kVK_RightControl,
        ]
        for modifier in modifiers {
            postKey(CGKeyCode(modifier), down: false, flags: [], source: source)
        }
    }
}
