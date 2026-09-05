import AppKit
import Carbon.HIToolbox

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
    private init() {
        abortMonitor.filter.onCancel = { [weak self] reason in
            guard let self else { return }
            if reason == .interaction { self.abortLock.withLock { self.userInteracted = true } }
            self.cancel()
        }
        abortMonitor.onInterruption = { [weak self] in
            self?.abortLock.withLock { self?.userInteracted = true }
            self?.cancel()
            self?.recordFailure("Escape protection was interrupted. Typing stopped; retry only after permission is restored.")
        }
    }
    private let abortMonitor = KeyMonitor()
    private let abortLock = NSLock()
    private var userInteracted = false
    private var destinationPID: pid_t?
    private var contentAllowed: () -> Bool = { false }
    private var closingMarker = false
    private var heldKeys = Set<CGKeyCode>()
    private(set) var lastStatus = "Ready. Select an insertion point before typing."


    var onProgress: ((String) -> Void)?
    var onRunCompleted: ((Bool) -> Void)?
    var onRunStarted: ((ProfileSettings) -> Void)?
    var onFailure: ((String) -> Void)?
    private var keyHold: TimeInterval = 0 // Only accessed on the serial delivery queue.

    /// Fired on the main thread when typing starts (`true`) and when it ends
    /// (`false`) — whether it finished or was aborted. Drives the menu-bar
    /// "typing" icon and the Esc/hotkey abort monitor.
    var onTypingStateChange: ((Bool) -> Void)?

    private let delivery = DeliveryQueue()
    var isTyping: Bool { delivery.isTyping }

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
              preTypeDelay: TimeInterval = 0,
              target: CapturedTarget) {
        let prefs = Preferences.shared
        let settingsSnapshot = ProfileSettings(preferences: prefs)
        let plan = TextProcessing.typingPlan(
            for: rawText,
            workaround: prefs.indentWorkaround,
            stripTrailingNewline: prefs.stripTrailingNewline,
            appendReturn: prefs.pressReturnAfterTyping)

        // Nothing to type → never engage typing state or post a focus click.
        guard !plan.isEmpty else { return }

        // Resolve once on the caller's main thread. A run never rereads settings
        // or the input layout after its safety checks.
        let mapper = prefs.typingMode == .keycodes ? KeyMapper() : nil
        if prefs.strictKeycodes && prefs.typingMode == .keycodes,
           !PasteSafety.passesStrictPreflight(plan: plan, mappingAvailable: mapper != nil,
                maps: { mapper?.stroke(for: $0) != nil }) {
            recordFailure("Cannot type this clipboard using the current keyboard layout. Strict keycode mode stopped before clicking or typing. No clipboard text is shown.")
            return
        }
        guard !delivery.isTyping else { return }
        guard abortMonitor.start() else {
            recordFailure(abortMonitor.unavailableReason)
            return
        }
        abortLock.withLock { userInteracted = false }
        guard let generation = delivery.begin() else { abortMonitor.stop(); return }
        onRunStarted?(settingsSnapshot)
        setTyping(true)

        let keystrokeDelayMs = settingsSnapshot.keystrokeDelayMs
        let workaround = prefs.indentWorkaround
        let hold = TimeInterval(settingsSnapshot.keyHoldMs) / 1000
        let newlineDelay = TimeInterval(settingsSnapshot.newlineDelayMs) / 1000
        delivery.submit { [weak self] in
            self?.run(plan: plan, generation: generation, keystrokeDelayMs: keystrokeDelayMs,
                      workaround: workaround, focusPoint: focusPoint,
                      settleDelay: settleDelay, preTypeDelay: preTypeDelay, mapper: mapper,
                      hold: hold, newlineDelay: newlineDelay, target: target)
        }
    }

    /// Request that in-progress (and already-queued) typing stop as soon as
    /// possible. Thread-safe.
    func cancel() {
        delivery.cancel()
    }

    private func isCancelled(_ generation: Int) -> Bool {
        delivery.isCancelled(generation)
    }

    private func run(plan: [TypingInstruction], generation: Int, keystrokeDelayMs: Int,
                     workaround: IndentWorkaround, focusPoint: CGPoint?,
                     settleDelay: TimeInterval, preTypeDelay: TimeInterval, mapper: KeyMapper?,
                     hold: TimeInterval, newlineDelay: TimeInterval, target: CapturedTarget) {
        var completed = false
        defer {
            contentAllowed = { false }
            destinationPID = nil
            delivery.finish()
            stopAbortMonitorWhenIdle()
            setTyping(false)
            let success = completed
            DispatchQueue.main.async { [weak self] in self?.onRunCompleted?(success) }
        }
        destinationPID = target.identity.pid
        guard let source = SyntheticEventTag.makeSource() else {
            recordFailure("Could not create tagged input events. Nothing was typed.")
            return
        }
        keyHold = hold
        let runner = DeliveryRunner(cancelled: { self.isCancelled(generation) })
        report("Waiting for focus and released modifiers…")
        // Physical state only: synthetic modifiers must not extend this wait.
        let released = {
            CGEventSource.flagsState(.hidSystemState)
                .intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty
        }
        let active = {
            self.abortMonitor.isHealthy && DispatchQueue.main.sync { TargetApplication.matches(target) }
        }
        var clickTargetLost = false
        let focus: () -> Void = {
            DispatchQueue.main.sync {
                if let focusPoint {
                    guard TargetApplication.remainsAtPoint(target, point: focusPoint) else {
                        clickTargetLost = true
                        self.cancel()
                        return
                    }
                    MouseClicker.click(at: focusPoint)
                } else {
                    // Preserve the existing insertion point. No synthetic mouse event.
                    NSRunningApplication(processIdentifier: target.identity.pid)?
                        .activate(options: [.activateIgnoringOtherApps])
                }
            }
        }
        let preparation = runner.prepare(settleDelay: settleDelay, focusDelay: preTypeDelay,
            modifiersReleased: released, focus: focus, targetReady: active)
        guard preparation == .posted else {
            if preparation == .targetNotReady || clickTargetLost {
                recordFailure("The selected window was unavailable, did not become active, or modifiers remained held. Nothing was typed.")
            } else { report("Cancelled before typing.") }
            return
        }
        abortMonitor.beginDelivery()
        var targetLost = false
        let streamReady = {
            if !active() { targetLost = true }
            return !targetLost
        }
        contentAllowed = {
            streamReady() && (self.closingMarker || !self.isCancelled(generation))
        }
        var lastReport = Date.distantPast
        let outcome = runner.run(plan: plan,
            characterDelay: TimeInterval(min(10000, max(0, keystrokeDelayMs))) / 1000,
            newlineDelay: newlineDelay, bracketed: workaround == .bracketedPaste,
            targetReady: streamReady,
            permitsCleanup: { !self.abortLock.withLock { self.userInteracted } && self.abortMonitor.isHealthy },
            executeCleanup: { instruction in
                self.closingMarker = true
                self.execute(instruction, source: source, mapper: mapper)
                self.closingMarker = false
            },
            execute: { instruction in
                autoreleasepool { self.execute(instruction, source: source, mapper: mapper) }
            }, progress: { count in
                if count == plan.count || Date().timeIntervalSince(lastReport) >= 0.1 {
                    self.report("Posted \(count) of \(plan.count) steps. Receipt unverified.")
                    lastReport = Date()
                }
            }, cleanup: { self.releaseModifiers(source: source) })
        if outcome == .targetChanged || targetLost {
            if IsSecureEventInputEnabled() {
                recordFailure("Stopped because Secure Input became active and Escape protection was unavailable. Check the original editor before retrying.")
                return
            }
            recordFailure("Stopped because the selected application/window changed or Escape protection was lost. No automatic retry. Check the original editor before continuing.")
        } else if outcome == .cancelled {
            report("Cancelled. Some input may already have reached the target; check the original editor.")
        } else {
            completed = true
            report("Finished posting \(plan.count) steps. Receipt is unverified; check the target.")
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lastStatus = message
            self?.onProgress?(message)
        }
    }
    func recordFailure(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lastStatus = message
            self?.onFailure?(message)
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

    private func stopAbortMonitorWhenIdle() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.delivery.isTyping else { return }
            self.abortMonitor.stop()
        }
    }

    private func setTyping(_ typing: Bool) {
        let state = delivery.isTyping
        DispatchQueue.main.async { [weak self] in
            self?.onTypingStateChange?(state)
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
        if keyHold > 0 { Thread.sleep(forTimeInterval: keyHold) }
        postKey(keyCode, down: false, flags: flags, source: source)

        if flags.contains(.maskAlternate) {
            postKey(CGKeyCode(kVK_Option), down: false, flags: [], source: source)
        }
        if flags.contains(.maskShift) {
            postKey(CGKeyCode(kVK_Shift), down: false, flags: [], source: source)
        }
    }

    private func postKey(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags, source: CGEventSource?) {
        guard let pid = destinationPID else { return }
        if down {
            guard contentAllowed() else { return }
        } else {
            guard heldKeys.remove(keyCode) != nil else { return }
        }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags
        if down { heldKeys.insert(keyCode) }
        event.postToPid(pid)
    }

    // MARK: - Unicode engine

    private func injectUnicode(_ character: Character, source: CGEventSource?) {
        let units = Array(String(character).utf16)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }

        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)

        guard let pid = destinationPID, contentAllowed() else { return }
        down.postToPid(pid)
        if keyHold > 0 { Thread.sleep(forTimeInterval: keyHold) }
        up.postToPid(pid)
    }

    // MARK: - Abort safety

    /// Post key-up for every modifier we might synthesize, so aborting mid-stroke
    /// can never leave Shift/Option/Command/Control stuck down. A key-up for a key
    /// that isn't down is a harmless no-op.
    private func releaseModifiers(source: CGEventSource?) {
        for key in Array(heldKeys) {
            postKey(key, down: false, flags: [], source: source)
        }
    }

    // MARK: - Special keys

    /// Fire a single key or chord (Ctrl-Alt-Del, Ctrl-C, a function key, an arrow) at
    /// whatever application currently has keyboard focus. Runs off the main thread on a
    /// serial delivery queue after cancelling typing, and balances its modifiers so nothing is
    /// left held down.
    func sendSpecialKey(_ key: SpecialKey, target: CapturedTarget?) {
        guard let target else { recordFailure("No focused target window was identified. Nothing was sent."); return }
        guard abortMonitor.start() else { recordFailure(abortMonitor.unavailableReason); return }
        delivery.interrupt({ [weak self] cancelled in
            guard let self else { return }
            defer {
                self.contentAllowed = { false }
                self.destinationPID = nil
            }
            let runner = DeliveryRunner(cancelled: cancelled)
            guard runner.wait(0.25), runner.awaitReady({
                self.abortMonitor.isHealthy && DispatchQueue.main.sync { TargetApplication.matches(target) }
            }) else { return }
            self.destinationPID = target.identity.pid
            self.abortMonitor.beginDelivery()
            self.contentAllowed = {
                !cancelled() && self.abortMonitor.isHealthy
                    && DispatchQueue.main.sync { TargetApplication.matches(target) }
            }
            self.postChord(keyCode: key.keyCode, flags: key.flags)
        }, completion: { [weak self] in
            guard let self else { return }
            self.stopAbortMonitorWhenIdle()
            self.setTyping(false)
        })
        setTyping(true)
    }

    /// Physically press every modifier in `flags`, tap the key, then release the
    /// modifiers in reverse — the same real-key modelling the keycode engine uses, which
    /// VNC/KVM targets track (they key off hardware modifier state, not event flags). A
    /// short settle after pressing the modifiers gives a slow remote console time to see
    /// them before the key lands.
    private func postChord(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = SyntheticEventTag.makeSource() else {
            recordFailure("Could not create tagged input events. No special key was sent.")
            return
        }
        let settle: useconds_t = 10_000 // 10 ms

        var modifiers: [CGKeyCode] = []
        if flags.contains(.maskControl)   { modifiers.append(CGKeyCode(kVK_Control)) }
        if flags.contains(.maskAlternate) { modifiers.append(CGKeyCode(kVK_Option)) }
        if flags.contains(.maskShift)     { modifiers.append(CGKeyCode(kVK_Shift)) }
        if flags.contains(.maskCommand)   { modifiers.append(CGKeyCode(kVK_Command)) }

        for modifier in modifiers {
            postKey(modifier, down: true, flags: flags, source: source)
        }
        if !modifiers.isEmpty { usleep(settle) }

        postKey(keyCode, down: true, flags: flags, source: source)
        postKey(keyCode, down: false, flags: flags, source: source)

        if !modifiers.isEmpty { usleep(settle) }
        for modifier in modifiers.reversed() {
            postKey(modifier, down: false, flags: [], source: source)
        }
    }
}

/// A discrete key or key-combo Peck can fire on demand at the focused app — for the
/// keys clipboard typing never sends (Ctrl-Alt-Del, interrupts, function keys, arrows)
/// that KVM/IPMI/noVNC/RDP console work needs.
struct SpecialKey {
    let title: String
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    init(_ title: String, keyCode: Int, flags: CGEventFlags = []) {
        self.title = title
        self.keyCode = CGKeyCode(keyCode)
        self.flags = flags
    }
}

/// The curated set surfaced in the menu-bar "Send Key" submenu. Grouped so the menu
/// stays organised; extend the arrays to add more.
enum SpecialKeyCatalog {
    /// The marquee one: Ctrl-Alt-Del for KVM/IPMI login screens and Windows. "Delete"
    /// here is the PC Delete key (forward delete), not Backspace.
    static let primary: [SpecialKey] = [
        SpecialKey("Ctrl-Alt-Delete", keyCode: kVK_ForwardDelete, flags: [.maskControl, .maskAlternate]),
    ]

    /// Common console interrupts / control keys.
    static let interrupts: [SpecialKey] = [
        SpecialKey("Escape", keyCode: kVK_Escape),
        SpecialKey("Ctrl-C  (interrupt)", keyCode: kVK_ANSI_C, flags: .maskControl),
        SpecialKey("Ctrl-D  (EOF)", keyCode: kVK_ANSI_D, flags: .maskControl),
        SpecialKey("Ctrl-Z  (suspend)", keyCode: kVK_ANSI_Z, flags: .maskControl),
    ]

    static let functionKeys: [SpecialKey] = [
        SpecialKey("F1", keyCode: kVK_F1), SpecialKey("F2", keyCode: kVK_F2),
        SpecialKey("F3", keyCode: kVK_F3), SpecialKey("F4", keyCode: kVK_F4),
        SpecialKey("F5", keyCode: kVK_F5), SpecialKey("F6", keyCode: kVK_F6),
        SpecialKey("F7", keyCode: kVK_F7), SpecialKey("F8", keyCode: kVK_F8),
        SpecialKey("F9", keyCode: kVK_F9), SpecialKey("F10", keyCode: kVK_F10),
        SpecialKey("F11", keyCode: kVK_F11), SpecialKey("F12", keyCode: kVK_F12),
    ]

    static let arrowKeys: [SpecialKey] = [
        SpecialKey("Up", keyCode: kVK_UpArrow), SpecialKey("Down", keyCode: kVK_DownArrow),
        SpecialKey("Left", keyCode: kVK_LeftArrow), SpecialKey("Right", keyCode: kVK_RightArrow),
    ]
}
