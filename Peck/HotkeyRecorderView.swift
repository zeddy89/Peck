import AppKit
import Carbon.HIToolbox

/// A small AppKit control for recording a global hotkey with no third-party libs.
/// Click it to enter recording mode, then press a modifier+key combination; it
/// captures the virtual keycode and Carbon modifier mask and reports them via
/// `onCapture`. Esc cancels recording without changing the current binding.
final class HotkeyRecorderView: NSView {

    /// Reports a newly recorded (keyCode, carbonModifiers).
    var onCapture: ((Int, Int) -> Void)?

    private(set) var keyCode: Int
    private(set) var carbonModifiers: Int
    private var isRecording = false

    /// When false the control is dimmed and won't record (hotkey disabled).
    var isEnabledForRecording = true {
        didSet {
            if !isEnabledForRecording { isRecording = false }
            updateAppearance()
        }
    }

    private let label = NSTextField(labelWithString: "")

    init(keyCode: Int, carbonModifiers: Int) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        super.init(frame: NSRect(x: 0, y: 0, width: 170, height: 24))

        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1

        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 6),
            heightAnchor.constraint(equalToConstant: 24),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Update the displayed binding without going through recording (e.g. on load).
    func set(keyCode: Int, carbonModifiers: Int) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        isRecording = false
        updateAppearance()
    }

    override var acceptsFirstResponder: Bool { isEnabledForRecording }

    // MARK: - Recording

    override func mouseDown(with event: NSEvent) {
        guard isEnabledForRecording else { return }
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        updateAppearance()
    }

    private func stopRecording() {
        isRecording = false
        updateAppearance()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    /// Command-based combos are delivered as key equivalents before keyDown, so we
    /// intercept them here while recording (otherwise ⌘Q etc. would hit the menu).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 { // Esc cancels recording
            stopRecording()
            return
        }

        let carbon = Self.carbonModifiers(from: event.modifierFlags)
        let code = Int(event.keyCode)

        guard HotkeyFormatter.isValid(keyCode: code, carbonModifiers: carbon) else {
            NSSound.beep() // needs a Command/Option/Control modifier plus a known key
            return
        }

        keyCode = code
        carbonModifiers = carbon
        isRecording = false
        updateAppearance()
        onCapture?(code, carbon)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }
        updateAppearance(pendingModifiers: Self.carbonModifiers(from: event.modifierFlags))
    }

    // MARK: - Appearance

    private func updateAppearance(pendingModifiers: Int? = nil) {
        if isRecording {
            let mods = pendingModifiers ?? carbonModifiers
            let prefix = HotkeyFormatter.modifierSymbols(carbonModifiers: mods)
            label.stringValue = prefix.isEmpty ? "Type shortcut…" : "\(prefix)…"
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            label.stringValue = HotkeyFormatter.displayString(keyCode: keyCode, carbonModifiers: carbonModifiers)
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
        label.textColor = isEnabledForRecording ? .labelColor : .disabledControlTextColor
        alphaValue = isEnabledForRecording ? 1.0 : 0.5
    }

    // MARK: - Conversion

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        return carbon
    }
}
