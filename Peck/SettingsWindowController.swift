import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {

    /// First Bool selects current-focus (true) or crosshair (false).
    var onHotkeyToggle: ((Bool, Bool) -> Bool)?
    var onHotkeyChanged: ((Bool, Int, Int) -> Bool)?
    var onBeforeSettingsChange: (() -> Void)?
    var onImportProfile: (() -> Void)?
    var onExportProfile: (() -> Void)?
    var onTypingTest: (() -> Void)?
    var onBasic: (() -> Void)?
    var onValuesChanged: (() -> Void)?

    private let presetPopup = NSPopUpButton()
    private let holdField = NSTextField()
    private let newlineDelayField = NSTextField()
    private let strictCheckbox = NSButton(checkboxWithTitle: "Stop if a character cannot map to a key", target: nil, action: nil)
    private let confirmationCheckbox = NSButton(checkboxWithTitle: "Confirm before typing when a warning applies", target: nil, action: nil)
    private let returnWarningCheckbox = NSButton(checkboxWithTitle: "Confirm any Return presses", target: nil, action: nil)
    private let preDelayField = NSTextField()
    private let keyDelayField = NSTextField()
    private let thresholdField = NSTextField()
    private let modePopup = NSPopUpButton()
    private let indentPopup = NSPopUpButton()
    private let hotkeyCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let recorderView = HotkeyRecorderView(
        keyCode: Preferences.shared.hotkeyKeyCode,
        carbonModifiers: Preferences.shared.hotkeyCarbonModifiers)
    private let focusHotkeyCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let focusRecorder = HotkeyRecorderView(keyCode: Preferences.shared.currentFocusHotkeyKeyCode,
        carbonModifiers: Preferences.shared.currentFocusHotkeyModifiers)
    private let pressReturnCheckbox = NSButton(
        checkboxWithTitle: "Press Return after typing", target: nil, action: nil)
    private let stripNewlineCheckbox = NSButton(
        checkboxWithTitle: "Strip one trailing newline from clipboard", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Launch at login", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 730),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Peck Advanced"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = PeckPalette.background
        window.minSize = NSSize(width: 650, height: 500)
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

        for field in [holdField, newlineDelayField] {
            field.formatter = integerFormatter
            field.alignment = .right
            field.delegate = self
        }
        let holdFormatter = NumberFormatter()
        holdFormatter.minimum = 0
        holdFormatter.maximum = 100
        holdField.formatter = holdFormatter
        presetPopup.addItems(withTitles: Preferences.Preset.allCases.map(\.title))
        presetPopup.target = self
        presetPopup.action = #selector(applyPreset)
        preDelayField.formatter = integerFormatter
        preDelayField.alignment = .right
        preDelayField.delegate = self
        keyDelayField.formatter = integerFormatter
        keyDelayField.alignment = .right
        keyDelayField.delegate = self

        let thresholdFormatter = NumberFormatter()
        thresholdFormatter.numberStyle = .none
        thresholdFormatter.minimum = 0
        thresholdFormatter.maximum = 10_000_000
        thresholdField.formatter = thresholdFormatter
        thresholdField.alignment = .right
        thresholdField.delegate = self

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
        focusHotkeyCheckbox.target = self
        focusHotkeyCheckbox.action = #selector(focusHotkeyEnableToggled)

        // Apply popup/checkbox changes the moment they're made. Waiting for the
        // window to close was a trap: change the mode, peck with the window still
        // open, and the old mode silently runs.
        for control: NSControl in [modePopup, indentPopup, pressReturnCheckbox, stripNewlineCheckbox, strictCheckbox, returnWarningCheckbox, confirmationCheckbox] {
            control.target = self
            control.action = #selector(applyImmediateSettings)
        }

        recorderView.onCapture = { [weak self] code, modifiers in
            _ = self?.onHotkeyChanged?(false, code, modifiers)
            self?.loadValues()
        }
        focusRecorder.onCapture = { [weak self] code, modifiers in
            _ = self?.onHotkeyChanged?(true, code, modifiers)
            self?.loadValues()
        }

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginToggled)

        let thresholdHint = caption(
            "0 disables the size warning only. Above the limit, Peck shows the character "
            + "and line count before typing.")

        let modeCaption = caption(
            "Console timings are starting points, not verified vSphere/KVM speeds. "
            + "Strict mode checks the whole clipboard before clicking. Layouts must match locally and remotely.")
        let indentCaption = caption(
            "Overwrite indent uses macOS shortcuts; do not use it in vi or remote consoles. "
            + "For Vim/vi, use :set paste AND enter Insert mode before typing. :set paste alone does not enter Insert mode. Some vi versions do not support it. "
            + "Experimental Vim bracketed paste requires supported Vim, not unknown vi; Peck never sends mode-entry commands.")

        let profileButtons = NSStackView(views: [
            NSButton(title: "Import Profile…", target: self, action: #selector(importProfile)),
            NSButton(title: "Export Profile…", target: self, action: #selector(exportProfile)),
        ])
        profileButtons.spacing = 10
        var sectionRows: [Int] = []
        var rows: [[NSView]] = []
        func section(_ title: String) {
            sectionRows.append(rows.count)
            let heading = label(title)
            heading.font = .systemFont(ofSize: 17, weight: .semibold)
            rows.append([heading, NSGridCell.emptyContentView])
        }
        section("Typing")
        rows += [
            [label("Apply preset:"), presetPopup],
            [label("Delay before typing (ms):"), preDelayField],
            [label("Keystroke delay (ms):"), keyDelayField],
            [label("Key hold (0–100 ms):"), holdField],
            [label("Extra delay after Return (ms):"), newlineDelayField],
            [label("Typing mode:"), modePopup],
            [label("Auto-indent workaround:"), indentPopup],
            [NSGridCell.emptyContentView, indentCaption],
        ]
        section("Shortcuts")
        rows += [
            [label("Crosshair hotkey:"), hotkeyCheckbox],
            [label("Crosshair shortcut:"), recorderView],
            [label("Current-focus hotkey:"), focusHotkeyCheckbox],
            [label("Current-focus shortcut:"), focusRecorder],
        ]
        section("Confirmation & safeguards")
        rows += [
            [NSGridCell.emptyContentView, confirmationCheckbox],
            [NSGridCell.emptyContentView, returnWarningCheckbox],
            [label("Confirm paste over (chars):"), thresholdField],
            [NSGridCell.emptyContentView, thresholdHint],
            [NSGridCell.emptyContentView, strictCheckbox],
            [NSGridCell.emptyContentView, pressReturnCheckbox],
            [NSGridCell.emptyContentView, stripNewlineCheckbox],
        ]
        section("Tools & startup")
        rows += [
            [label("Check delivery:"), NSButton(title: "Typing Test & Calibration…", target: self, action: #selector(openTypingTest))],
            [label("Share settings:"), profileButtons],
            [NSGridCell.emptyContentView, launchAtLoginCheckbox],
            [NSGridCell.emptyContentView, modeCaption],
        ]
        let grid = NSGridView(views: rows)
        for row in sectionRows {
            grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: row, length: 1))
            grid.cell(atColumnIndex: 0, rowIndex: row).xPlacement = .leading
            grid.row(at: row).topPadding = row == 0 ? 0 : 18
            grid.row(at: row).bottomPadding = 6
        }
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedSettingsView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyDown
        let heading = label("Peck")
        heading.font = .systemFont(ofSize: 28, weight: .semibold)
        let subheading = label("Advanced settings")
        subheading.font = .systemFont(ofSize: 15)
        subheading.textColor = PeckPalette.secondary
        let titles = NSStackView(views: [heading, subheading])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 3
        let back = NSButton(title: "Basic", target: self, action: #selector(openBasic))
        back.bezelStyle = .rounded
        back.image = NSImage(systemSymbolName: "arrow.left", accessibilityDescription: nil)
        back.imagePosition = .imageLeading
        let header = NSStackView(views: [icon, titles, NSView(), back])
        header.spacing = 16
        header.alignment = .centerY
        let divider = NSBox()
        divider.boxType = .separator
        let layout = NSStackView(views: [header, divider, grid])
        layout.orientation = .vertical
        layout.alignment = .leading
        layout.spacing = 22
        layout.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(layout)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            layout.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            layout.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24),
            layout.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            layout.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            header.widthAnchor.constraint(equalTo: layout.widthAnchor),
            divider.widthAnchor.constraint(equalTo: layout.widthAnchor),
            grid.widthAnchor.constraint(equalTo: layout.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),
            preDelayField.widthAnchor.constraint(equalToConstant: 80),
            keyDelayField.widthAnchor.constraint(equalToConstant: 80),
            holdField.widthAnchor.constraint(equalToConstant: 80),
            newlineDelayField.widthAnchor.constraint(equalToConstant: 80),
            thresholdField.widthAnchor.constraint(equalToConstant: 80),
            thresholdHint.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            modeCaption.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            indentCaption.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.textColor = PeckPalette.ink
        return field
    }

    private func caption(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = PeckPalette.secondary
        return field
    }

    // MARK: - Immediate-effect actions

    /// Popups and checkboxes take effect as soon as they're changed. Text fields
    /// still commit on close (mid-edit values shouldn't apply keystroke-by-keystroke).
    @objc private func applyImmediateSettings() {
        onBeforeSettingsChange?()
        let prefs = Preferences.shared
        presetPopup.selectItem(at: 0)
        prefs.strictKeycodes = strictCheckbox.state == .on
        prefs.confirmBeforeTyping = confirmationCheckbox.state == .on
        prefs.warnOnReturn = returnWarningCheckbox.state == .on
        prefs.typingMode = Preferences.TypingMode(rawValue: modePopup.indexOfSelectedItem) ?? .keycodes
        prefs.indentWorkaround = IndentWorkaround(rawValue: indentPopup.indexOfSelectedItem) ?? .none
        prefs.pressReturnAfterTyping = pressReturnCheckbox.state == .on
        prefs.stripTrailingNewline = stripNewlineCheckbox.state == .on
        onValuesChanged?()
    }

    /// Persist a numeric field the moment its edit commits (Return, Tab, or focus loss),
    /// not only when the window closes. The status-item click and the global hotkey fire
    /// regardless of which window is frontmost, so a committed-but-unsaved threshold edit
    /// would otherwise let a paste run against the stale saved guardrail value.
    func controlTextDidEndEditing(_ obj: Notification) {
        onBeforeSettingsChange?()
        let prefs = Preferences.shared
        presetPopup.selectItem(at: 0)
        prefs.keyHoldMs = holdField.integerValue
        holdField.integerValue = prefs.keyHoldMs
        prefs.newlineDelayMs = newlineDelayField.integerValue
        prefs.preTypeDelayMs = min(10000, max(0, preDelayField.integerValue))
        prefs.keystrokeDelayMs = min(10000, max(0, keyDelayField.integerValue))
        prefs.largePasteThreshold = thresholdField.integerValue
        onValuesChanged?()
    }

    @objc private func applyPreset() {
        onBeforeSettingsChange?()
        let selected = presetPopup.indexOfSelectedItem
        // Finish numeric editing before applying a preset, never afterward.
        window?.makeFirstResponder(nil)
        let preset = Preferences.Preset(rawValue: selected) ?? .custom
        Preferences.shared.apply(preset)
        loadValues()
        presetPopup.selectItem(at: selected)
        onValuesChanged?()
    }

    @objc private func hotkeyEnableToggled() {
        _ = onHotkeyToggle?(false, hotkeyCheckbox.state == .on)
        loadValues()
    }
    @objc private func focusHotkeyEnableToggled() {
        _ = onHotkeyToggle?(true, focusHotkeyCheckbox.state == .on)
        loadValues()
    }
    @objc private func openBasic() { window?.close(); onBasic?() }
    @objc private func openTypingTest() { onTypingTest?() }
    @objc private func importProfile() { onImportProfile?() }
    @objc private func exportProfile() { onExportProfile?() }

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
        holdField.integerValue = prefs.keyHoldMs
        newlineDelayField.integerValue = prefs.newlineDelayMs
        strictCheckbox.state = prefs.strictKeycodes ? .on : .off
        confirmationCheckbox.state = prefs.confirmBeforeTyping ? .on : .off
        returnWarningCheckbox.state = prefs.warnOnReturn ? .on : .off
        preDelayField.integerValue = prefs.preTypeDelayMs
        keyDelayField.integerValue = prefs.keystrokeDelayMs
        thresholdField.integerValue = prefs.largePasteThreshold
        modePopup.selectItem(at: prefs.typingMode.rawValue)
        indentPopup.selectItem(at: prefs.indentWorkaround.rawValue)
        focusHotkeyCheckbox.state = prefs.currentFocusHotkeyEnabled ? .on : .off
        focusRecorder.set(keyCode: prefs.currentFocusHotkeyKeyCode, carbonModifiers: prefs.currentFocusHotkeyModifiers)
        focusRecorder.isEnabledForRecording = true
        hotkeyCheckbox.state = prefs.hotkeyEnabled ? .on : .off
        recorderView.set(keyCode: prefs.hotkeyKeyCode, carbonModifiers: prefs.hotkeyCarbonModifiers)
        recorderView.isEnabledForRecording = true
        pressReturnCheckbox.state = prefs.pressReturnAfterTyping ? .on : .off
        stripNewlineCheckbox.state = prefs.stripTrailingNewline ? .on : .off
        launchAtLoginCheckbox.state = LoginItem.isEnabled ? .on : .off
    }

    private func saveValues() {
        onBeforeSettingsChange?()
        let prefs = Preferences.shared
        presetPopup.selectItem(at: 0)
        prefs.keyHoldMs = holdField.integerValue
        holdField.integerValue = prefs.keyHoldMs
        prefs.newlineDelayMs = newlineDelayField.integerValue
        prefs.preTypeDelayMs = min(10000, max(0, preDelayField.integerValue))
        prefs.keystrokeDelayMs = min(10000, max(0, keyDelayField.integerValue))
        prefs.largePasteThreshold = thresholdField.integerValue
        // Popups/checkboxes already applied live; re-apply for belt-and-suspenders.
        applyImmediateSettings()
        // Hotkey enable and shortcut are applied immediately via their own actions.
    }

    /// Commit any in-progress text-field edit, then persist. Called on window
    /// close and at app termination — quitting with the window open never fires
    /// `windowWillClose`, which would silently drop edited delay/threshold values.
    func commitPendingEdits() {
        window?.makeFirstResponder(nil)
        saveValues()
    }

    func windowWillClose(_ notification: Notification) {
        commitPendingEdits()
    }
}

private final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        PeckPalette.background.setFill()
        dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
