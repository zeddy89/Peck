import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    /// Fired when the global-hotkey enable checkbox is toggled (register/unregister).
    var onHotkeyToggle: ((Bool) -> Void)?
    /// Fired when a new shortcut is recorded (re-register if enabled).
    var onHotkeyChanged: (() -> Void)?

    private let preDelayField = NSTextField()
    private let keyDelayField = NSTextField()
    private let thresholdField = NSTextField()
    private let modePopup = NSPopUpButton()
    private let indentPopup = NSPopUpButton()
    private let hotkeyCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let recorderView = HotkeyRecorderView(
        keyCode: Preferences.shared.hotkeyKeyCode,
        carbonModifiers: Preferences.shared.hotkeyCarbonModifiers)
    private let pressReturnCheckbox = NSButton(
        checkboxWithTitle: "Press Return after typing", target: nil, action: nil)
    private let stripNewlineCheckbox = NSButton(
        checkboxWithTitle: "Strip trailing newline from clipboard", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Launch at login", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
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

        let thresholdFormatter = NumberFormatter()
        thresholdFormatter.numberStyle = .none
        thresholdFormatter.minimum = 0
        thresholdFormatter.maximum = 10_000_000
        thresholdField.formatter = thresholdFormatter
        thresholdField.alignment = .right

        modePopup.addItems(withTitles: [
            "Keycodes — best for VM consoles / noVNC / RDP",
            "Unicode — broadest character support",
        ])

        // Order must match IndentWorkaround's raw values (none / bracketedPaste / overwriteIndent).
        indentPopup.addItems(withTitles: [
            "Off — type exactly",
            "Bracketed paste — terminals & vim",
            "Overwrite indent — code editors",
        ])

        hotkeyCheckbox.target = self
        hotkeyCheckbox.action = #selector(hotkeyEnableToggled)

        recorderView.onCapture = { [weak self] keyCode, carbonModifiers in
            Preferences.shared.hotkeyKeyCode = keyCode
            Preferences.shared.hotkeyCarbonModifiers = carbonModifiers
            self?.onHotkeyChanged?()
        }

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginToggled)

        let thresholdHint = caption(
            "0 disables the confirmation. Above the limit, Peck shows the character "
            + "and line count before typing.")

        let modeCaption = caption(
            "Keycode mode presses real keys resolved from your current keyboard layout, "
            + "which remote consoles expect. Characters it can't map fall back to Unicode "
            + "injection automatically. Esc or the hotkey aborts an in-progress paste.")

        let indentCaption = caption(
            "Fixes double-indentation when a target auto-indents what Peck types. "
            + "Bracketed paste suits terminals/vim; overwrite indent suits GUI code "
            + "editors. Leave off for plain shells.")

        let grid = NSGridView(views: [
            [label("Delay before typing (ms):"), preDelayField],
            [label("Keystroke delay (ms):"), keyDelayField],
            [label("Typing mode:"), modePopup],
            [label("Auto-indent workaround:"), indentPopup],
            [NSGridCell.emptyContentView, indentCaption],
            [label("Confirm paste over (chars):"), thresholdField],
            [NSGridCell.emptyContentView, thresholdHint],
            [label("Global hotkey:"), hotkeyCheckbox],
            [label("Shortcut:"), recorderView],
            [NSGridCell.emptyContentView, pressReturnCheckbox],
            [NSGridCell.emptyContentView, stripNewlineCheckbox],
            [NSGridCell.emptyContentView, launchAtLoginCheckbox],
            [NSGridCell.emptyContentView, modeCaption],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            preDelayField.widthAnchor.constraint(equalToConstant: 80),
            keyDelayField.widthAnchor.constraint(equalToConstant: 80),
            thresholdField.widthAnchor.constraint(equalToConstant: 80),
            thresholdHint.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            modeCaption.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            indentCaption.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func caption(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        return field
    }

    // MARK: - Immediate-effect actions

    @objc private func hotkeyEnableToggled() {
        let enabled = hotkeyCheckbox.state == .on
        Preferences.shared.hotkeyEnabled = enabled
        recorderView.isEnabledForRecording = enabled
        onHotkeyToggle?(enabled)
    }

    @objc private func launchAtLoginToggled() {
        let wantEnabled = launchAtLoginCheckbox.state == .on
        if !LoginItem.setEnabled(wantEnabled) {
            let alert = NSAlert()
            alert.messageText = "Couldn't \(wantEnabled ? "enable" : "disable") launch at login"
            alert.informativeText = "macOS declined the change. If you're running Peck from a "
                + "temporary or unsigned location, move it to /Applications and try again."
            alert.runModal()
        }
        // Always reflect the real registration state, whether the change stuck or not.
        launchAtLoginCheckbox.state = LoginItem.isEnabled ? .on : .off
    }

    // MARK: - Load / save

    /// Re-read all controls from the current state. Called before the window is
    /// shown again so externally-changeable state (launch-at-login) isn't stale.
    func refresh() {
        loadValues()
    }

    private func loadValues() {
        let prefs = Preferences.shared
        preDelayField.integerValue = prefs.preTypeDelayMs
        keyDelayField.integerValue = prefs.keystrokeDelayMs
        thresholdField.integerValue = prefs.largePasteThreshold
        modePopup.selectItem(at: prefs.typingMode.rawValue)
        indentPopup.selectItem(at: prefs.indentWorkaround.rawValue)
        hotkeyCheckbox.state = prefs.hotkeyEnabled ? .on : .off
        recorderView.set(keyCode: prefs.hotkeyKeyCode, carbonModifiers: prefs.hotkeyCarbonModifiers)
        recorderView.isEnabledForRecording = prefs.hotkeyEnabled
        pressReturnCheckbox.state = prefs.pressReturnAfterTyping ? .on : .off
        stripNewlineCheckbox.state = prefs.stripTrailingNewline ? .on : .off
        launchAtLoginCheckbox.state = LoginItem.isEnabled ? .on : .off
    }

    private func saveValues() {
        let prefs = Preferences.shared
        prefs.preTypeDelayMs = preDelayField.integerValue
        prefs.keystrokeDelayMs = keyDelayField.integerValue
        prefs.largePasteThreshold = thresholdField.integerValue
        prefs.typingMode = Preferences.TypingMode(rawValue: modePopup.indexOfSelectedItem) ?? .keycodes
        prefs.indentWorkaround = IndentWorkaround(rawValue: indentPopup.indexOfSelectedItem) ?? .none
        prefs.pressReturnAfterTyping = pressReturnCheckbox.state == .on
        prefs.stripTrailingNewline = stripNewlineCheckbox.state == .on
        // Hotkey enable and shortcut are applied immediately via their own actions.
    }

    func windowWillClose(_ notification: Notification) {
        // Commit any in-progress text field edits, then persist.
        window?.makeFirstResponder(nil)
        saveValues()
    }
}
