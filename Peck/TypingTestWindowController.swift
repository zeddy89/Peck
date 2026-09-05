import AppKit

/// Only actual tagged keyboard edits can qualify a local trial. Paste, user edits,
/// and programmatic changes never stand in for received CGEvents.
private final class CalibrationReceiver: NSTextView {
    var onEdit: ((Bool) -> Void)?
    private var synthetic = false
    override func keyDown(with event: NSEvent) {
        synthetic = SyntheticEventTag.isSynthetic(event)
        defer { synthetic = false }
        super.keyDown(with: event)
    }
    override func didChangeText() {
        super.didChangeText()
        onEdit?(synthetic)
    }
}

final class TypingTestWindowController: NSWindowController, NSWindowDelegate {
    var onArm: (() -> Void)?
    var onSettings: (() -> Void)?
    private let receiver = CalibrationReceiver()
    private let status = NSTextField(wrappingLabelWithString: "Last run: Ready.")
    private let result = NSTextField(wrappingLabelWithString: "No comparison yet.")
    private let summary = NSTextField(wrappingLabelWithString: "Three fresh exact matches are required at each speed. No recommendation yet.")
    private let target = NSPopUpButton()
    private let rates = NSTextField(string: "15, 10, 5, 2")
    private let speed = NSPopUpButton()
    private var calibration: Calibration?
    private var trialSettings: ProfileSettings?
    private var sessionSettings: ProfileSettings?
    private var configuredRates = [15, 10, 5, 2]
    private var revision = 0
    private var syntheticOnly = true
    private var suppressEdits = false
    private var buttons: [NSButton] = []
    private var recommendationButton: NSButton!

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 780),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Peck Typing Test"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        window.minSize = NSSize(width: 800, height: 720)
        window.center()
        buildUI()
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        buttons.append(button)
        return button
    }
    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.spacing = 10
        return stack
    }
    private func buildUI() {
        guard let content = window?.contentView else { return }
        let instructions = NSTextField(wrappingLabelWithString:
            "Copy Sample, then Begin Trial to clear this editor and temporarily apply the selected delay. Arm Peck and click the receiving editor. In vi/Vim, enable :set paste AND enter Insert mode yourself. Never execute the sample.\nLocal trials require Peck’s actual keystrokes here. For Remote, use a fresh remote scratch file each time, copy its received text back here, then Record Result. Remote results are user-supplied, not independently verified.")
        target.addItems(withTitles: ["Local received keystrokes", "Remote (user-supplied receipt)"])
        target.target = self
        target.action = #selector(resetSession)
        rates.placeholderString = "Milliseconds, comma separated"
        rates.widthAnchor.constraint(equalToConstant: 130).isActive = true
        speed.addItems(withTitles: ["15 ms", "10 ms", "5 ms", "2 ms"])
        let configuration = row([target, NSTextField(labelWithString: "Rates:"), rates,
                                 button("Set Rates", #selector(setRates))])
        let trialRow = row([NSTextField(labelWithString: "Trial speed:"), speed,
            button("Begin Trial", #selector(beginTrial)), button("Record Result", #selector(recordResult))])
        let ordinary = row([button("Copy Sample", #selector(copySample)), button("Arm Peck", #selector(armPeck)),
            button("Compare Only", #selector(compareText)), button("Clear", #selector(clearText)),
            button("Settings…", #selector(openSettings))])
        recommendationButton = button("Apply Recommended", #selector(applyRecommended))
        recommendationButton.isEnabled = false
        let finish = row([recommendationButton, button("End Calibration / Restore Delay", #selector(endCalibration))])
        receiver.isRichText = false
        receiver.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        receiver.isAutomaticQuoteSubstitutionEnabled = false
        receiver.isAutomaticDashSubstitutionEnabled = false
        receiver.isAutomaticTextReplacementEnabled = false
        receiver.isAutomaticSpellingCorrectionEnabled = false
        receiver.isContinuousSpellCheckingEnabled = false
        receiver.allowsUndo = false
        receiver.isVerticallyResizable = true
        receiver.textContainerInset = NSSize(width: 8, height: 8)
        receiver.autoresizingMask = [.width]
        receiver.textContainer?.widthTracksTextView = true
        receiver.onEdit = { [weak self] synthetic in
            guard let self, !self.suppressEdits else { return }
            self.revision += 1
            self.syntheticOnly = self.syntheticOnly && synthetic
        }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = receiver
        let stack = NSStackView(views: [instructions, ordinary, configuration, trialRow, summary,
                                       scroll, result, finish, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            instructions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            summary.widthAnchor.constraint(equalTo: stack.widthAnchor),
            result.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    func updateStatus(_ message: String) { status.stringValue = "Last run: " + message }
    func typingStateChanged(_ typing: Bool) {
        buttons.forEach { $0.isEnabled = !typing }
        target.isEnabled = !typing
        rates.isEnabled = !typing
        speed.isEnabled = !typing
        recommendationButton.isEnabled = !typing && calibration?.recommendedDelay != nil
    }
    func deliveryStarted(settings: ProfileSettings) {
        calibration?.runStarted(configurationMatches: settings == trialSettings)
    }
    func deliveryFinished(success: Bool) {
        calibration?.runFinished(success: success)
        if !success {
            calibration?.cancelTrial()
            restoreOwnedDelay()
        }
    }

    private func parsedRates() throws -> [Int] {
        let pieces = rates.stringValue.split(separator: ",", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == pieces.count else { throw Calibration.Failure.invalidRates }
        return try Calibration(candidates: numbers, target: .local, originalDelay: 0).candidates
    }
    @objc private func setRates() {
        guard !Typist.shared.isTyping else { return }
        do {
            let numbers = try parsedRates()
            restoreDelay()
            configuredRates = numbers
            speed.removeAllItems()
            speed.addItems(withTitles: numbers.map { "\($0) ms" })
            result.stringValue = "Rates updated. Begin a fresh calibration trial."
            refreshSummary()
        } catch { result.stringValue = "Use 1–12 distinct whole-number delays from 0 to 10000 ms." }
    }
    @objc private func resetSession() {
        guard !Typist.shared.isTyping else { return }
        restoreDelay()
        clearReceiver()
        refreshSummary()
    }
    @objc private func beginTrial() {
        guard !Typist.shared.isTyping else { return }
        do {
            guard try parsedRates() == configuredRates else {
                result.stringValue = "Choose Set Rates before beginning with edited rates."
                return
            }
            if let baseline = sessionSettings {
                var current = ProfileSettings(preferences: .shared)
                current.keystrokeDelayMs = baseline.keystrokeDelayMs
                guard current == baseline else {
                    restoreDelay()
                    refreshSummary()
                    result.stringValue = "Other settings changed. Previous calibration scores were discarded. Begin Trial again."
                    return
                }
            }
            if calibration == nil {
                calibration = try Calibration(candidates: parsedRates(),
                    target: Calibration.Target(rawValue: target.indexOfSelectedItem) ?? .local,
                    originalDelay: Preferences.shared.keystrokeDelayMs)
                sessionSettings = ProfileSettings(preferences: .shared)
            }
            guard let delay = speed.titleOfSelectedItem?.split(separator: " ").first.flatMap({ Int($0) }) else { return }
            clearReceiver()
            try calibration?.begin(delay: delay, revision: revision)
            Preferences.shared.keystrokeDelayMs = delay
            trialSettings = ProfileSettings(preferences: .shared)
            result.stringValue = "Fresh \(delay) ms trial. Arm Peck and send the sample once. Then record the received text."
            refreshSummary()
        } catch { result.stringValue = "Set valid rates before beginning a trial." }
    }
    @objc private func recordResult() {
        guard !Typist.shared.isTyping else { return }
        guard calibration != nil else { result.stringValue = "Begin Trial first. Compare Only does not qualify a speed."; return }
        guard ProfileSettings(preferences: .shared) == trialSettings else {
            calibration?.cancelTrial()
            result.stringValue = "Settings changed during this trial. Begin a fresh trial at consistent settings."
            return
        }
        do {
            let exact = Array(receiver.string.unicodeScalars) == Array(TypingFixture.text.unicodeScalars)
            try calibration?.record(exact: exact, revision: revision, syntheticOnly: syntheticOnly)
            result.stringValue = TypingFixture.comparison(received: receiver.string)
                + (calibration?.target == .remote ? " User-supplied remote result only." : "")
            refreshSummary()
        } catch {
            result.stringValue = "Not recorded. Each trial needs one completed Peck run and fresh received text. Local trials reject pasted/manual text. Begin Trial again after cancellation or a consumed result."
        }
    }
    private func refreshSummary() {
        guard let calibration else {
            summary.stringValue = "Three fresh exact matches are required at each speed. No recommendation yet."
            recommendationButton.isEnabled = false
            return
        }
        let scores = calibration.candidates.map { delay -> String in
            let score = calibration.scores[delay, default: Calibration.Score()]
            return "\(delay) ms: \(score.matches)/3 matches, \(score.mismatches) mismatches"
        }.joined(separator: "  •  ")
        let recommended = calibration.recommendedDelay.map { "Recommended: \($0) ms." }
            ?? "No speed has qualified yet. After a mismatch, test a slower speed."
        summary.stringValue = scores + "\n" + recommended
            + (calibration.target == .remote ? " Remote evidence is user-supplied." : " Local receiver only; remote compatibility unverified.")
        recommendationButton.isEnabled = calibration.recommendedDelay != nil
    }
    private func restoreOwnedDelay() {
        if let delay = calibration?.restorationDelay(current: Preferences.shared.keystrokeDelayMs) {
            Preferences.shared.keystrokeDelayMs = delay
        }
    }
    private func restoreDelay() {
        restoreOwnedDelay()
        calibration = nil
        trialSettings = nil
        sessionSettings = nil
    }
    @objc private func endCalibration() {
        guard !Typist.shared.isTyping else { return }
        restoreDelay()
        clearReceiver()
        refreshSummary()
        result.stringValue = "Calibration ended. Its delay was restored unless you changed that setting separately."
    }
    @objc private func applyRecommended() {
        guard !Typist.shared.isTyping else { return }
        var current = ProfileSettings(preferences: .shared)
        if let baseline = sessionSettings { current.keystrokeDelayMs = baseline.keystrokeDelayMs }
        guard let delay = calibration?.recommendation(configurationMatches: current == sessionSettings) else {
            restoreDelay()
            refreshSummary()
            result.stringValue = "Settings changed or no speed qualified. Start a fresh calibration for this configuration."
            return
        }
        Preferences.shared.keystrokeDelayMs = delay
        calibration = nil
        trialSettings = nil
        sessionSettings = nil
        clearReceiver()
        refreshSummary()
        result.stringValue = "Applied \(delay) ms. This changes only the character delay; repeat testing for a different target."
    }
    private func clearReceiver() {
        suppressEdits = true
        receiver.string = ""
        suppressEdits = false
        revision += 1
        syntheticOnly = true
    }
    @objc private func copySample() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TypingFixture.text, forType: .string)
        result.stringValue = "Sample copied. Begin a fresh trial before sending it."
    }
    @objc private func armPeck() {
        guard AccessibilityGate.check(prompt: true) else {
            result.stringValue = "Accessibility permission is required. Enable Peck in System Settings > Privacy & Security > Accessibility, then try Arm Peck again."
            return
        }
        onArm?()
    }
    @objc private func openSettings() { onSettings?() }
    @objc private func compareText() {
        guard !Typist.shared.isTyping else { return }
        result.stringValue = TypingFixture.comparison(received: receiver.string)
    }
    @objc private func clearText() {
        guard !Typist.shared.isTyping else { return }
        calibration?.cancelTrial()
        restoreOwnedDelay()
        clearReceiver()
        result.stringValue = "Cleared. Begin Trial before recording another result."
    }
    func windowWillClose(_ notification: Notification) {
        endSessionForTermination()
    }
    func endSessionForTermination() {
        Typist.shared.cancel()
        restoreDelay()
        clearReceiver()
        refreshSummary()
        result.stringValue = "No comparison yet."
    }
}
