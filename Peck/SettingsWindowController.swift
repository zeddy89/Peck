import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    var onHotkeyToggle: ((Bool) -> Void)?

    private let preDelayField = NSTextField()
    private let keyDelayField = NSTextField()
    private let modePopup = NSPopUpButton()
    private let hotkeyCheckbox = NSButton(checkboxWithTitle: "Enable global hotkey  ⌃⌥⌘V", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "Peck Settings"
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)
        window.delegate = self
        buildUI()
        loadValues()
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let integerFormatter = NumberFormatter()
        integerFormatter.numberStyle = .none
        integerFormatter.minimum = 0
        integerFormatter.maximum = 10_000

        preDelayField.formatter = integerFormatter
        preDelayField.alignment = .right
        keyDelayField.formatter = integerFormatter
        keyDelayField.alignment = .right

        modePopup.addItems(withTitles: [
            "Keycodes — best for VM consoles / noVNC / RDP",
            "Unicode — broadest character support",
        ])

        let caption = NSTextField(wrappingLabelWithString:
            "Keycode mode presses real keys resolved from your current keyboard layout, "
            + "which remote consoles expect. Characters it can't map fall back to Unicode "
            + "injection automatically.")
        caption.font = NSFont.systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [label("Delay before typing (ms):"), preDelayField],
            [label("Keystroke delay (ms):"), keyDelayField],
            [label("Typing mode:"), modePopup],
            [NSGridCell.emptyContentView, hotkeyCheckbox],
            [NSGridCell.emptyContentView, caption],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            preDelayField.widthAnchor.constraint(equalToConstant: 80),
            keyDelayField.widthAnchor.constraint(equalToConstant: 80),
            caption.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    // MARK: - Load / save

    private func loadValues() {
        let prefs = Preferences.shared
        preDelayField.integerValue = prefs.preTypeDelayMs
        keyDelayField.integerValue = prefs.keystrokeDelayMs
        modePopup.selectItem(at: prefs.typingMode.rawValue)
        hotkeyCheckbox.state = prefs.hotkeyEnabled ? .on : .off
    }

    private func saveValues() {
        let prefs = Preferences.shared
        prefs.preTypeDelayMs = preDelayField.integerValue
        prefs.keystrokeDelayMs = keyDelayField.integerValue
        prefs.typingMode = Preferences.TypingMode(rawValue: modePopup.indexOfSelectedItem) ?? .keycodes

        let hotkeyOn = hotkeyCheckbox.state == .on
        if hotkeyOn != prefs.hotkeyEnabled {
            prefs.hotkeyEnabled = hotkeyOn
            onHotkeyToggle?(hotkeyOn)
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Commit any in-progress text field edits, then persist.
        window?.makeFirstResponder(nil)
        saveValues()
    }
}
