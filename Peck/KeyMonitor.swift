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


/// Production event-tap decision. No characters are stored, only whether a
/// swallowed Escape still needs its matching key-up swallowed.
final class InputAbortFilter {
    enum Decision { case pass, swallow }
    enum Reason { case escape, interaction }
    var onCancel: ((Reason) -> Void)?
    private let lock = NSLock()
    private var engaged = false
    private var delivering = false
    private var swallowingEscape = false

    func begin() { lock.withLock { engaged = true; delivering = false } }
    func beginDelivery() { lock.withLock { delivering = true } }
    func end() { lock.withLock { engaged = false; delivering = false } }

    func handle(type: CGEventType, event: CGEvent) -> Decision {
        if event.getIntegerValueField(.eventSourceUserData) == SyntheticEventTag.magic { return .pass }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        var reason: Reason?
        let decision: Decision = lock.withLock {
            if type == .keyUp && key == 53 && swallowingEscape {
                swallowingEscape = false
                return .swallow
            }
            if type == .keyDown && key == 53 && (engaged || swallowingEscape) {
                swallowingEscape = true
                if engaged { reason = .escape }
                return .swallow
            }
            if engaged && delivering && [CGEventType.keyDown, .flagsChanged, .leftMouseDown,
                                           .rightMouseDown, .otherMouseDown].contains(type) {
                reason = .interaction
            }
            return .pass
        }
        // Synchronous: generation is cancelled before the real event reaches vi.
        if let reason { onCancel?(reason) }
        return decision
    }
}

/// A filtering session tap, not an observing NSEvent global monitor. Keyboard
/// events are requested separately so missing keyboard permission cannot be
/// mistaken for a working tap that happens to receive only mouse events.
final class KeyMonitor {
    var onInterruption: (() -> Void)?
    let filter = InputAbortFilter()
    private var taps: [CFMachPort] = []
    private var sources: [CFRunLoopSource] = []
    private let lock = NSLock()
    private var healthy = false

    static func protectionAvailable(tapEnabled: Bool, secureInput: Bool) -> Bool {
        tapEnabled && !secureInput
    }

    var isHealthy: Bool {
        Self.protectionAvailable(tapEnabled: lock.withLock { healthy }
            && taps.allSatisfy { CGEvent.tapIsEnabled(tap: $0) },
            secureInput: IsSecureEventInputEnabled())
    }

    var unavailableReason: String {
        if IsSecureEventInputEnabled() {
            return "Secure Input is active, so Peck cannot protect Escape. Nothing was typed. Close the app or field holding Secure Input, then retry."
        }
        return "Cannot protect Escape. Enable Peck in Accessibility and Input Monitoring if macOS requests it, then retry. Nothing was typed."
    }

    func start() -> Bool {
        precondition(Thread.isMainThread)
        if taps.isEmpty {
            let keyMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            let otherMask = [CGEventType.flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
                .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
            for mask in [CGEventMask(keyMask), otherMask] {
                guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                    options: .defaultTap, eventsOfInterest: mask,
                    callback: { _, type, event, context in
                        guard let context else { return Unmanaged.passUnretained(event) }
                        return Unmanaged<KeyMonitor>.fromOpaque(context).takeUnretainedValue()
                            .handle(type: type, event: event)
                    }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
                    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                    tearDown()
                    return false
                }
                taps.append(tap)
                sources.append(source)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        for tap in taps { CGEvent.tapEnable(tap: tap, enable: true) }
        lock.withLock { healthy = true }
        guard isHealthy else { return false }
        filter.begin()
        return true
    }

    func beginDelivery() { filter.beginDelivery() }
    func stop() {
        // Keep taps alive to swallow a held Escape's key-up after cancellation.
        // Inactive filtering passes every other event unchanged.
        filter.end()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.withLock { healthy = false }
            onInterruption?()
            return Unmanaged.passUnretained(event)
        }
        return filter.handle(type: type, event: event) == .swallow ? nil : Unmanaged.passUnretained(event)
    }

    private func tearDown() {
        for (tap, source) in zip(taps, sources) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(tap)
        }
        taps.removeAll()
        sources.removeAll()
        lock.withLock { healthy = false }
    }
    deinit { tearDown() }
}
