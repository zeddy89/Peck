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

    /// Enqueue clipboard text to be typed. Returns immediately; typing proceeds on
    /// the dedicated queue and can be stopped with `cancel()`.
    func type(_ rawText: String) {
        let generation = lock.withLock { () -> Int in
            _generation += 1
            return _generation
        }
        queue.async { [weak self] in
            self?.run(rawText, generation: generation)
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

    private func run(_ rawText: String, generation: Int) {
        let prefs = Preferences.shared
        let plan = TextProcessing.typingPlan(
            for: rawText,
            workaround: prefs.indentWorkaround,
            stripTrailingNewline: prefs.stripTrailingNewline,
            appendReturn: prefs.pressReturnAfterTyping)

        guard !plan.isEmpty else { return }

        let source = SyntheticEventTag.makeSource()
        let delayMicroseconds = UInt32(max(0, prefs.keystrokeDelayMs)) * 1_000
        let mapper = makeMapperIfNeeded()

        setTyping(true)
        defer { setTyping(false) }

        for instruction in plan {
            if isCancelled(generation) {
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
            if delayMicroseconds > 0 {
                usleep(delayMicroseconds)
            }
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
