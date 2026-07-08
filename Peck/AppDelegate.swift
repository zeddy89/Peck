import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let targeting = TargetingController()
    private let hotkey = HotkeyManager()
    private let abortMonitor = KeyMonitor()
    private lazy var settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = Self.icon(armed: false)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Peck — click to arm, right-click for menu"
        }

        targeting.onStateChange = { [weak self] armed in
            self?.refreshIcon(armed: armed)
        }

        // While typing, the hotkey aborts instead of arming; otherwise it toggles
        // targeting. Esc (via the abort monitor) also cancels an in-progress paste.
        hotkey.onActivate = { [weak self] in
            guard let self else { return }
            if Typist.shared.isTyping {
                Typist.shared.cancel()
            } else {
                self.targeting.toggle()
            }
        }
        if Preferences.shared.hotkeyEnabled {
            hotkey.register()
        }

        // Drive the abort monitor and the "typing" icon from typing state (fired on
        // the main thread by Typist).
        Typist.shared.onTypingStateChange = { [weak self] typing in
            guard let self else { return }
            typing ? self.abortMonitor.start() : self.abortMonitor.stop()
            self.isTyping = typing
            self.refreshIcon(armed: self.targeting.isArmed)
        }
        abortMonitor.onEscape = {
            Typist.shared.cancel()
        }

        settings.onHotkeyToggle = { [weak self] enabled in
            if enabled { self?.hotkey.register() } else { self?.hotkey.unregister() }
        }
        settings.onHotkeyChanged = { [weak self] in
            guard let self, Preferences.shared.hotkeyEnabled else { return }
            if !self.hotkey.reregister() {
                // The combo is likely already claimed by another app.
                NSSound.beep()
            }
        }

        // Nudge the Accessibility prompt at first launch so the user
        // grants it before they actually need it.
        _ = AccessibilityGate.check(prompt: true)
    }

    private var isTyping = false

    private func refreshIcon(armed: Bool) {
        statusItem.button?.image = Self.icon(armed: armed, typing: isTyping)
    }

    // MARK: - Status item

    private static func icon(armed: Bool, typing: Bool = false) -> NSImage? {
        let name: String
        if typing {
            name = "keyboard.fill" // distinct glyph while a paste is being typed
        } else if armed {
            name = "dot.scope"
        } else {
            name = "scope"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Peck")
            ?? NSImage(systemSymbolName: "scope", accessibilityDescription: "Peck")
        image?.isTemplate = true
        return image
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        let isRightClick = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)

        if isRightClick {
            showMenu()
        } else if Typist.shared.isTyping {
            // A left-click while typing aborts, matching the hotkey's behavior.
            Typist.shared.cancel()
        } else {
            targeting.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let armTitle: String
        if Typist.shared.isTyping {
            armTitle = "Abort Typing"
        } else {
            armTitle = targeting.isArmed ? "Cancel Targeting" : "Arm Targeting"
        }
        let armItem = NSMenuItem(title: armTitle, action: #selector(toggleTargeting), keyEquivalent: "")
        armItem.target = self
        menu.addItem(armItem)

        if Preferences.shared.hotkeyEnabled {
            let shortcut = HotkeyFormatter.displayString(
                keyCode: Preferences.shared.hotkeyKeyCode,
                carbonModifiers: Preferences.shared.hotkeyCarbonModifiers)
            let hint = NSMenuItem(title: "Global hotkey:  \(shortcut)", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        if !AccessibilityGate.check(prompt: false) {
            let axItem = NSMenuItem(
                title: "⚠︎ Grant Accessibility Permission…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: "")
            axItem.target = self
            menu.addItem(axItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Peck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        // Attach + present as one unit. Guarding on the button ensures we never leave
        // a menu attached without a matching present/close cycle (which would make
        // every later left-click reopen the menu instead of arming).
        guard let button = statusItem.button else { return }
        statusItem.menu = menu
        button.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detach so the next left-click arms targeting instead of reopening the menu.
        // Defer to the next runloop turn so the dismissing mouse-up finishes with the
        // menu still attached — otherwise clicking the icon to close an open menu could
        // fall through to the button's action and arm unintentionally.
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    // MARK: - Actions

    @objc private func toggleTargeting() {
        if Typist.shared.isTyping {
            Typist.shared.cancel()
        } else {
            targeting.toggle()
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settings.refresh() // re-sync externally-changeable state (e.g. launch-at-login)
        settings.showWindow(nil)
        settings.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
