import Foundation

struct TargetIdentity: Equatable {
    let pid: Int32
    let windowID: UInt32
}

/// The same cancellable schedule drives production and deterministic tests.
/// `execute` must balance a stroke's key-down/key-up before returning.
struct DeliveryRunner {
    enum Outcome: Equatable { case posted, cancelled, targetNotReady, targetChanged }
    var cancelled: () -> Bool
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }

    func wait(_ seconds: TimeInterval) -> Bool {
        var remaining = max(0, seconds)
        while remaining > 0 {
            if cancelled() { return false }
            let step = min(0.02, remaining)
            sleep(step)
            remaining -= step
        }
        return !cancelled()
    }

    func awaitReady(_ ready: () -> Bool, timeout: TimeInterval = 5) -> Bool {
        var elapsed: TimeInterval = 0
        var stable: TimeInterval = 0
        while elapsed < timeout {
            if cancelled() { return false }
            stable = ready() ? stable + 0.02 : 0
            if stable >= 0.1 { return true }
            if !wait(0.02) { return false }
            elapsed += 0.02
        }
        return false
    }

    func prepare(settleDelay: TimeInterval, focusDelay: TimeInterval,
                 modifiersReleased: () -> Bool, focus: (() -> Void)?,
                 targetReady: () -> Bool) -> Outcome {
        guard awaitReady(modifiersReleased) else { return cancelled() ? .cancelled : .targetNotReady }
        if let focus {
            guard wait(settleDelay) else { return .cancelled }
            focus()
            guard awaitReady({ modifiersReleased() && targetReady() }) else {
                return cancelled() ? .cancelled : .targetNotReady
            }
        }
        guard wait(focusDelay) else { return .cancelled }
        // Recheck after the delay in case activation changed while settling.
        guard awaitReady({ modifiersReleased() && targetReady() }) else {
            return cancelled() ? .cancelled : .targetNotReady
        }
        return .posted
    }

    func run(plan: [TypingInstruction], characterDelay: TimeInterval,
             newlineDelay: TimeInterval, bracketed: Bool,
             targetReady: @escaping () -> Bool = { true },
             permitsCleanup: () -> Bool = { true },
             executeCleanup: ((TypingInstruction) -> Void)? = nil,
             execute: (TypingInstruction) -> Void,
             progress: (Int) -> Void, cleanup: () -> Void) -> Outcome {
        var needsClose = false
        var targetLost = false
        let monitored = DeliveryRunner(cancelled: {
            if !targetReady() { targetLost = true }
            return self.cancelled() || targetLost
        }, sleep: sleep)
        defer {
            if needsClose && !targetLost && permitsCleanup() {
                for instruction in TextProcessing.bracketedPasteMarker(open: false) {
                    guard targetReady() else { break }
                    if let executeCleanup { executeCleanup(instruction) } else { execute(instruction) }
                }
            }
            cleanup()
        }
        let length = TextProcessing.bracketedPasteMarkerLength
        let closeStart = plan.count - length - (plan.last == .key(.returnKey) ? 1 : 0)
        var index = 0
        while index < plan.count {
            if !targetReady() { targetLost = true; return .targetChanged }
            if cancelled() { return .cancelled }
            // A marker is atomic so cancellation cannot leave a partial ESC sequence.
            let marker = bracketed && (index == 0 || index == closeStart)
            let end = marker ? index + length : index + 1
            for instruction in plan[index..<end] {
                guard targetReady() else { targetLost = true; return .targetChanged }
                execute(instruction)
            }
            if marker { needsClose = index == 0 }
            let last = plan[end - 1]
            index = end
            progress(index)
            if !monitored.wait(characterDelay + (last == .key(.returnKey) ? newlineDelay : 0)) {
                return targetLost ? .targetChanged : .cancelled
            }
        }
        return .posted
    }
}

enum PasteSafety {
    /// Routine paste confirmation is opt-in. Permission, mapping and destination
    /// checks remain separate and cannot be disabled by this preference.
    static func shouldConfirm(typedCount: Int, returns: Int, confirmationEnabled: Bool,
                              warnOnReturn: Bool, threshold: Int) -> Bool {
        confirmationEnabled && ((warnOnReturn && returns > 0) || (threshold > 0 && typedCount > threshold))
    }
    static func passesStrictPreflight(plan: [TypingInstruction], mappingAvailable: Bool,
                                      maps: (Character) -> Bool) -> Bool {
        mappingAvailable && unsupportedCount(in: plan, maps: maps) == 0
    }
    static func returnCount(in plan: [TypingInstruction]) -> Int {
        plan.filter { $0 == .key(.returnKey) }.count
    }
    static func unsupportedCount(in plan: [TypingInstruction], maps: (Character) -> Bool) -> Int {
        plan.reduce(0) { count, instruction in
            if case .key(.literal(let character)) = instruction, !maps(character) { return count + 1 }
            return count
        }
    }
}

/// No clipboard contents are included in a comparison report.
enum TypingFixture {
    static let text = """
    aaa()bbb
    111(222)333
    () () () () ()
    [] {} () <>
    aA1! bB2@ cC3#
    # L006 indentation and continuation
    def sample():
        values = [1, 2, 3]
        for value in values:
            print(value)
        return values
    command = "example " \\
        "--reasoning on " \\
        "--reasoning-effort low"
    L015|0123456789|abcdefghijklmnopqrstuvwxyz|ABCDEFGHIJKLMNOPQRSTUVWXYZ|END
    L016 END PECK TEST
    """
    static func comparison(received: String) -> String {
        // Compare scalar sequences, not Swift's canonically-equivalent Characters.
        let expected = Array(text.unicodeScalars)
        let actual = Array(received.unicodeScalars)
        if expected == actual { return "Exact match: all \(expected.count) Unicode scalars received. Local editor only; remote consoles remain unverified." }
        let index = zip(expected, actual).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(expected.count, actual.count)
        let prefix = expected.prefix(index)
        let line = prefix.filter { $0 == "\n" }.count + 1
        let column = prefix.reversed().prefix { $0 != "\n" }.count + 1
        return "Mismatch at line \(line), column \(column) (scalar \(index + 1)). Expected \(expected.count), received \(actual.count) scalars. No received text is logged."
    }
}

/// All synthetic output shares this queue. Interrupts cancel pending paste work
/// before queuing their chord, so balanced key-up and bracket cleanup finish first.
final class DeliveryQueue {
    private let queue = DispatchQueue(label: "dev.homelab.peck.delivery", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0
    private var cancelledThrough = 0
    private var active = false
    private var pendingSpecials = 0
    var isTyping: Bool { lock.withLock { active || pendingSpecials > 0 } }
    func begin() -> Int? {
        lock.withLock {
            guard !active && pendingSpecials == 0 else { return nil }
            generation += 1
            active = true
            return generation
        }
    }
    func finish() { lock.withLock { active = false } }
    func cancel() { lock.withLock { cancelledThrough = generation } }
    func isCancelled(_ token: Int) -> Bool { lock.withLock { cancelledThrough >= token } }
    func submit(_ operation: @escaping () -> Void) { queue.async(execute: DispatchWorkItem(block: operation)) }
    func interrupt(_ operation: @escaping (@escaping () -> Bool) -> Void, completion: @escaping () -> Void = {}) {
        let token = lock.withLock { () -> Int in
            cancelledThrough = generation
            generation += 1
            pendingSpecials += 1
            return generation
        }
        submit {
            operation { self.isCancelled(token) }
            self.lock.withLock { self.pendingSpecials -= 1 }
            completion()
        }
    }
}
