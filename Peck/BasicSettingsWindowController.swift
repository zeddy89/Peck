import AppKit
import Carbon.HIToolbox

enum PeckPalette {
    static func color(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
    static let background = color(light: 0xFAF8F2, dark: 0x152428)
    static let ink = color(light: 0x10383E, dark: 0xF4F3EB)
    static let secondary = color(light: 0x476268, dark: 0xB7CACD)
    static let line = color(light: 0xC9C7BF, dark: 0x4D6268)
    static let selected = color(light: 0x103C43, dark: 0x235B65)
    static let orange = NSColor(srgbRed: 0.97, green: 0.42, blue: 0.08, alpha: 1)
}

private final class PeckBackground: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        PeckPalette.background.setFill()
        dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// Real NSButtons retain native keyboard activation and accessibility behavior.
private final class SpeedButton: NSButton {
    let choice: Preferences.SpeedChoice
    init(_ choice: Preferences.SpeedChoice) {
        self.choice = choice
        super.init(frame: .zero)
        title = "\(choice.title), \(choice.rawValue) ms"
        setButtonType(.toggle)
        isBordered = false
        focusRingType = .exterior
        setAccessibilityLabel("\(choice.title), \(choice.rawValue) milliseconds between keystrokes")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !isEnabled { NSGraphicsContext.current?.cgContext.setAlpha(0.5) }
        let selected = state == .on
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        (selected ? PeckPalette.selected : PeckPalette.background).setFill()
        box.fill()
        (selected ? PeckPalette.selected : PeckPalette.line).setStroke()
        box.lineWidth = 1
        box.stroke()
        if selected {
            PeckPalette.orange.setFill()
            NSBezierPath(ovalIn: NSRect(x: 13, y: 14, width: 9, height: 9)).fill()
        }
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let foreground = selected ? NSColor.white : PeckPalette.ink
        (choice.title as NSString).draw(in: NSRect(x: 6, y: 27, width: bounds.width - 12, height: 27), withAttributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: foreground, .paragraphStyle: center,
        ])
        ("\(choice.rawValue) ms" as NSString).draw(in: NSRect(x: 6, y: 54, width: bounds.width - 12, height: 23), withAttributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: selected ? NSColor(white: 0.9, alpha: 1) : PeckPalette.secondary,
            .paragraphStyle: center,
        ])
    }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

private final class ShortcutKeycap: NSView {
    override func draw(_ dirtyRect: NSRect) {
        PeckPalette.line.setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        outline.lineWidth = 1
        outline.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class BasicSettingsWindowController: NSWindowController, NSWindowDelegate {
    var onAdvanced: (() -> Void)?
    var onSpeed: ((Preferences.SpeedChoice) -> Void)?
    var statusProvider: (() -> (failed: Bool, armed: Bool, message: String))?
    private var choices: [SpeedButton] = []
    private let shortcut = NSTextField(labelWithString: "")
    private let pacing = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let statusDot = NSTextField(labelWithString: "●")
    private let login = NSSwitch()
    private var refreshTimer: Timer?

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Peck"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = PeckPalette.background
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
        refresh()
    }
    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = PeckPalette.ink
        return field
    }
    private func buildUI() {
        guard let window else { return }
        let content = PeckBackground(frame: NSRect(x: 0, y: 0, width: 540, height: 520))
        window.contentView = content
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = label("Peck", size: 30, weight: .semibold)
        let tagline = label("Copy. Focus. Peck.", size: 16)
        tagline.textColor = PeckPalette.secondary
        let nameStack = NSStackView(views: [name, tagline])
        nameStack.orientation = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 3
        let version = label(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", size: 12)
        version.textColor = PeckPalette.secondary
        let header = NSStackView(views: [icon, nameStack, NSView(), version])
        header.spacing = 18
        header.alignment = .centerY
        let divider = NSBox()
        divider.boxType = .separator
        let speedTitle = label("Typing speed", size: 17, weight: .semibold)
        choices = Preferences.SpeedChoice.allCases.map {
            let button = SpeedButton($0)
            button.target = self
            button.action = #selector(selectSpeed(_:))
            return button
        }
        let speeds = NSStackView(views: choices)
        speeds.distribution = .fillEqually
        speeds.spacing = 9
        for button in choices { button.heightAnchor.constraint(equalToConstant: 96).isActive = true }
        pacing.font = .systemFont(ofSize: 11)
        pacing.textColor = PeckPalette.secondary
        pacing.lineBreakMode = .byTruncatingTail
        let shortcutTitle = label("Paste shortcut", size: 17, weight: .semibold)
        shortcut.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        shortcut.textColor = PeckPalette.ink
        let changeHint = label("Change in Advanced", size: 12)
        changeHint.textColor = PeckPalette.secondary
        let keycap = ShortcutKeycap()
        shortcut.translatesAutoresizingMaskIntoConstraints = false
        keycap.addSubview(shortcut)
        NSLayoutConstraint.activate([
            shortcut.leadingAnchor.constraint(equalTo: keycap.leadingAnchor, constant: 14),
            shortcut.trailingAnchor.constraint(equalTo: keycap.trailingAnchor, constant: -14),
            shortcut.topAnchor.constraint(equalTo: keycap.topAnchor, constant: 8),
            shortcut.bottomAnchor.constraint(equalTo: keycap.bottomAnchor, constant: -8),
        ])
        let shortcutRow = NSStackView(views: [keycap, NSView(), changeHint])
        shortcutRow.alignment = .centerY
        let loginTitle = label("Launch at login", size: 17, weight: .semibold)
        login.target = self
        login.action = #selector(toggleLogin)
        login.setAccessibilityLabel("Launch Peck at login")
        let loginRow = NSStackView(views: [loginTitle, NSView(), login])
        loginRow.alignment = .centerY
        let bottomDivider = NSBox()
        bottomDivider.boxType = .separator
        let advanced = NSButton(title: "Advanced…", target: self, action: #selector(openAdvanced))
        advanced.bezelStyle = .rounded
        advanced.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        advanced.imagePosition = .imageLeading
        status.font = .systemFont(ofSize: 12)
        status.textColor = PeckPalette.secondary
        status.lineBreakMode = .byTruncatingTail
        let statusRow = NSStackView(views: [statusDot, status])
        statusRow.spacing = 6
        let bottom = NSStackView(views: [advanced, NSView(), statusRow])
        bottom.alignment = .centerY
        let escape = label("Esc stops typing.", size: 12)
        escape.textColor = PeckPalette.secondary
        escape.alignment = .center

        let stack = NSStackView(views: [header, divider, speedTitle, speeds, pacing,
                                      shortcutTitle, shortcutRow, loginRow, bottomDivider, bottom, escape])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(21, after: header)
        stack.setCustomSpacing(20, after: divider)
        stack.setCustomSpacing(5, after: speeds)
        stack.setCustomSpacing(20, after: pacing)
        stack.setCustomSpacing(21, after: shortcutRow)
        stack.setCustomSpacing(20, after: loginRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -12),
            icon.widthAnchor.constraint(equalToConstant: 64), icon.heightAnchor.constraint(equalToConstant: 64),
            speeds.heightAnchor.constraint(equalToConstant: 96),
            statusRow.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
        ] + [header, divider, speeds, pacing, shortcutRow, loginRow, bottomDivider, bottom, escape].map {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor)
        })
    }

    override func showWindow(_ sender: Any?) {
        refresh()
        super.showWindow(sender)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        let prefs = Preferences.shared
        for button in choices {
            button.state = prefs.speedChoice == button.choice ? .on : .off
            button.isEnabled = !Typist.shared.isTyping
            button.needsDisplay = true
        }
        let custom = prefs.speedChoice == nil ? "Custom: \(prefs.keystrokeDelayMs) ms. " : ""
        let extras = prefs.keyHoldMs > 0 || prefs.newlineDelayMs > 0
            ? "Additional timing: \(prefs.keyHoldMs) ms hold, \(prefs.newlineDelayMs) ms after Return."
            : "Delay between keystrokes."
        pacing.stringValue = custom + extras
        pacing.toolTip = pacing.stringValue
        shortcut.stringValue = prefs.currentFocusHotkeyEnabled
            ? HotkeyFormatter.displayString(keyCode: prefs.currentFocusHotkeyKeyCode, carbonModifiers: prefs.currentFocusHotkeyModifiers)
            : "Shortcut disabled"
        shortcut.setAccessibilityLabel("Paste at current focus: " + shortcut.stringValue)
        login.state = LoginItem.isEnabled ? .on : .off
        let context = statusProvider?()
        let text: String
        let ready: Bool
        if Typist.shared.isTyping { text = "Typing…"; ready = true }
        else if context?.armed == true { text = "Choose a target"; ready = true }
        else if !AccessibilityGate.check(prompt: false) { text = "Accessibility needed"; ready = false }
        else if IsSecureEventInputEnabled() { text = "Secure Input active"; ready = false }
        else if context?.failed == true { text = "Last run stopped"; ready = false }
        else { text = "Ready to start"; ready = true }
        status.stringValue = text
        status.toolTip = context?.message ?? "Target and Escape protection are checked when a run starts."
        statusDot.textColor = ready ? PeckPalette.ink : PeckPalette.orange
    }
    @objc private func selectSpeed(_ sender: SpeedButton) { onSpeed?(sender.choice); refresh() }
    @objc private func openAdvanced() { onAdvanced?() }
    @objc private func toggleLogin() {
        if !LoginItem.setEnabled(login.state == .on) {
            let alert = NSAlert()
            alert.messageText = "Launch at login could not be changed"
            alert.informativeText = "macOS declined the change. Try again after moving Peck to Applications."
            alert.runModal()
        }
        refresh()
    }
    func windowDidBecomeKey(_ notification: Notification) { refresh() }
    func windowWillClose(_ notification: Notification) { refreshTimer?.invalidate(); refreshTimer = nil }
}
