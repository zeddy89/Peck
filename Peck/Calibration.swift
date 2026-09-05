import Foundation

/// Aggregate-only trial bookkeeping. Received text belongs to the ephemeral UI.
struct Calibration {
    enum Target: Int { case local, remote }
    enum Failure: Error { case invalidRates, noTrial, unfinished, staleReceipt, untrustedLocalReceipt, consumed }
    struct Score: Equatable { var matches = 0; var mismatches = 0 }
    struct Trial {
        let delay: Int
        let initialRevision: Int
        var started = false
        var finished = false
        var successful = false
        var consumed = false
    }
    let candidates: [Int]
    let target: Target
    let originalDelay: Int
    private(set) var lastAppliedDelay: Int?
    private(set) var scores: [Int: Score] = [:]
    private(set) var trial: Trial?

    init(candidates: [Int], target: Target, originalDelay: Int) throws {
        guard !candidates.isEmpty, candidates.count <= 12,
              Set(candidates).count == candidates.count,
              candidates.allSatisfy({ (0...10000).contains($0) }) else { throw Failure.invalidRates }
        self.candidates = candidates.sorted(by: >)
        self.target = target
        self.originalDelay = originalDelay
    }

    mutating func begin(delay: Int, revision: Int) throws {
        guard candidates.contains(delay) else { throw Failure.invalidRates }
        trial = Trial(delay: delay, initialRevision: revision)
        lastAppliedDelay = delay
    }
    mutating func runStarted(configurationMatches: Bool = true) {
        guard trial != nil, trial?.consumed == false else { return }
        guard configurationMatches else { trial?.consumed = true; return }
        // One deliberate trial can contain only one delivery run.
        if trial?.started == true { trial?.consumed = true; return }
        trial?.started = true
    }
    mutating func runFinished(success: Bool) {
        guard trial?.started == true, trial?.consumed == false, trial?.finished == false else { return }
        trial?.finished = true
        trial?.successful = success
    }
    mutating func cancelTrial() { trial?.consumed = true }

    mutating func record(exact: Bool, revision: Int, syntheticOnly: Bool) throws {
        guard var current = trial else { throw Failure.noTrial }
        guard !current.consumed else { throw Failure.consumed }
        guard current.started && current.finished && current.successful else { throw Failure.unfinished }
        // No arriving text is a legitimate failure after a completed run, but
        // unchanged content can never count as a successful fresh receipt.
        guard revision > current.initialRevision || !exact else { throw Failure.staleReceipt }
        // Consume before rejecting provenance so a manually supplied local sample
        // cannot be edited into an apparently authentic successful trial.
        current.consumed = true
        trial = current
        guard target != .local || syntheticOnly else { throw Failure.untrustedLocalReceipt }
        var score = scores[current.delay, default: Score()]
        if exact { score.matches += 1 } else { score.mismatches += 1 }
        scores[current.delay] = score
    }

    var recommendedDelay: Int? {
        let failed = scores.filter { $0.value.mismatches > 0 }.map(\.key).max()
        return scores.filter {
            $0.value.matches >= 3 && $0.value.mismatches == 0 && (failed == nil || $0.key > failed!)
        }.map(\.key).min()
    }
    func recommendation(configurationMatches: Bool) -> Int? {
        configurationMatches ? recommendedDelay : nil
    }
    /// Restore only our pacing key, and only if it still has our last value.
    /// A separate settings edit must not be silently overwritten.
    func restorationDelay(current: Int) -> Int? {
        current == lastAppliedDelay ? originalDelay : nil
    }
}
