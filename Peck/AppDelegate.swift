import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let targeting = TargetingController()
    private let hotkey = HotkeyManager()
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
            self?.statusItem.button?.image = Self.icon(armed: armed)
        }

        hotkey.onActivate = { [weak self] in
            self?.targeting.toggle()
        }
        if Preferences.shared.hotkeyEnabled {
            hotkey.register()
        }

        settings.onHotkeyToggle = { [weak self] enabled in
            enabled ? self?.hotkey.register() : self?.hotkey.unregister()
        }

        // Nudge the Accessibility prompt at first launch so the user
        // grants it before they actually need it.
        _ = AccessibilityGate.check(prompt: true)
    }

    // MARK: - Status item

    private static func icon(armed: Bool) -> NSImage? {
        let name = armed ? "dot.scope" : "scope"
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
        } else {
            targeting.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let armTitle = targeting.isArmed ? "Cancel Targeting" : "Arm Targeting"
        let armItem = NSMenuItem(title: armTitle, action: #selector(toggleTargeting), keyEquivalent: "")
        armItem.target = self
        menu.addItem(armItem)

        if Preferences.shared.hotkeyEnabled {
            let hint = NSMenuItem(title: "Global hotkey:  ⌃⌥⌘V", action: nil, keyEquivalent: "")
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
        targeting.toggle()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settings.showWindow(nil)
        settings.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
