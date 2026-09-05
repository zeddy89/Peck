import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let targeting = TargetingController()
    private let hotkey = HotkeyManager(action: .crosshair)
    private let focusHotkey = HotkeyManager(action: .currentFocus)
    private var menuTarget: CapturedTarget?
    private var lastRunFailed = false
    private lazy var settings = SettingsWindowController()
    private lazy var basicSettings = BasicSettingsWindowController()
    private lazy var typingTest = TypingTestWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
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
            } else if NSApp.modalWindow == nil {
                self.targeting.toggle()
            }
        }
        focusHotkey.onActivate = { [weak self] in
            guard let self else { return }
            if Typist.shared.isTyping { Typist.shared.cancel(); return }
            if self.targeting.isArmed { self.targeting.disarm(); return }
            guard NSApp.modalWindow == nil else { return }
            // Capture before a confirmation can activate Peck.
            self.targeting.typeAtCurrentFocus(TargetApplication.current())
        }
        let prefs = Preferences.shared
        if prefs.hotkeyEnabled && !configureHotkey(currentFocus: false, enabled: true, showError: false) {
            prefs.hotkeyEnabled = false
        }
        if prefs.currentFocusHotkeyEnabled && !configureHotkey(currentFocus: true, enabled: true, showError: false) {
            prefs.currentFocusHotkeyEnabled = false
        }

        // Drive the abort monitor and the "typing" icon from typing state (fired on
        // the main thread by Typist).
        Typist.shared.onTypingStateChange = { [weak self] typing in
            guard let self else { return }
            if typing { self.lastRunFailed = false }
            self.typingTest.typingStateChanged(typing)
            self.isTyping = typing
            if !typing {
                self.statusItem.button?.title = ""
                self.statusItem.length = NSStatusItem.squareLength
            }
            self.refreshIcon(armed: self.targeting.isArmed)
        }
        Typist.shared.onRunStarted = { [weak self] settings in
            self?.typingTest.deliveryStarted(settings: settings)
        }
        Typist.shared.onRunCompleted = { [weak self] success in
            self?.typingTest.deliveryFinished(success: success)
        }
        Typist.shared.onProgress = { [weak self] message in
            guard let self else { return }
            // The existing status button never activates an app or steals target
            // focus. Clicking its visible × cancels just like Esc/the hotkey.
            self.typingTest.updateStatus(message)
            self.statusItem.button?.toolTip = message + (Typist.shared.isTyping ? " Click to cancel." : " Right-click for last status.")
            guard Typist.shared.isTyping else { return }
            let words = message.split(separator: " ")
            self.statusItem.button?.title = words.first == "Posted" && words.count > 3
                ? " \(words[1])/\(words[3]) ×" : " … ×"
            self.statusItem.length = NSStatusItem.variableLength
        }
        Typist.shared.onFailure = { [weak self] message in
            guard let self else { return }
            self.lastRunFailed = true
            self.statusItem.button?.toolTip = message
            self.typingTest.updateStatus(message)
            self.refreshIcon(armed: self.targeting.isArmed)
        }
        typingTest.onArm = { [weak self] in self?.targeting.toggle() }
        typingTest.onSettings = { [weak self] in self?.openSettings() }

        settings.onHotkeyToggle = { [weak self] currentFocus, enabled in
            self?.configureHotkey(currentFocus: currentFocus, enabled: enabled) ?? false
        }
        settings.onHotkeyChanged = { [weak self] currentFocus, code, modifiers in
            let prefs = Preferences.shared
            return self?.configureHotkey(currentFocus: currentFocus,
                enabled: currentFocus ? prefs.currentFocusHotkeyEnabled : prefs.hotkeyEnabled,
                candidate: HotkeyBinding(keyCode: code, modifiers: modifiers)) ?? false
        }
        settings.onBeforeSettingsChange = { [weak self] in self?.typingTest.endSessionForTermination() }
        settings.onImportProfile = { [weak self] in self?.importProfile() }
        settings.onExportProfile = { [weak self] in self?.exportProfile() }
        settings.onBasic = { [weak self] in self?.openSettings() }
        settings.onTypingTest = { [weak self] in self?.openTypingTest() }
        settings.onValuesChanged = { [weak self] in self?.basicSettings.refresh() }
        basicSettings.onAdvanced = { [weak self] in self?.openAdvanced() }
        basicSettings.onSpeed = { [weak self] choice in self?.applySpeed(choice) }
        basicSettings.statusProvider = { [weak self] in
            (failed: self?.lastRunFailed ?? false, armed: self?.targeting.isArmed ?? false,
             message: Typist.shared.lastStatus)
        }

        // Nudge the Accessibility prompt at first launch so the user
        // grants it before they actually need it.
        _ = AccessibilityGate.check(prompt: true)
        if !UserDefaults.standard.bool(forKey: "hasSeenBasicSettings") || CommandLine.arguments.contains("--show-settings") {
            UserDefaults.standard.set(true, forKey: "hasSeenBasicSettings")
            openSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows && !Typist.shared.isTyping { openSettings() }
        return true
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Peck")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Peck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @discardableResult
    private func configureHotkey(currentFocus: Bool, enabled: Bool,
                                 candidate: HotkeyBinding? = nil, showError: Bool = true) -> Bool {
        let prefs = Preferences.shared
        let selected = candidate ?? HotkeyBinding(
            keyCode: currentFocus ? prefs.currentFocusHotkeyKeyCode : prefs.hotkeyKeyCode,
            modifiers: currentFocus ? prefs.currentFocusHotkeyModifiers : prefs.hotkeyCarbonModifiers)
        let other = HotkeyBinding(keyCode: currentFocus ? prefs.hotkeyKeyCode : prefs.currentFocusHotkeyKeyCode,
            modifiers: currentFocus ? prefs.hotkeyCarbonModifiers : prefs.currentFocusHotkeyModifiers)
        let otherEnabled = currentFocus ? prefs.hotkeyEnabled : prefs.currentFocusHotkeyEnabled
        // At startup the original crosshair binding has priority; a new default
        // current-focus shortcut must not displace a saved custom crosshair key.
        let otherRegistered = currentFocus ? hotkey.binding != nil : focusHotkey.binding != nil
        let conflict = enabled && otherEnabled && (showError || otherRegistered) && selected == other
        let manager = currentFocus ? focusHotkey : hotkey
        guard selected.isValid && !conflict && (!enabled || manager.register(selected)) else {
            let message = "Could not register the \(currentFocus ? "current-focus" : "crosshair") shortcut. Choose a different Command/Option/Control combination. Any previously working binding was kept."
            Typist.shared.recordFailure(message)
            if showError {
                let alert = NSAlert()
                alert.messageText = "Shortcut unavailable"
                alert.informativeText = message
                alert.runModal()
            }
            return false
        }
        if !enabled { manager.unregister() }
        if currentFocus {
            prefs.currentFocusHotkeyKeyCode = selected.keyCode
            prefs.currentFocusHotkeyModifiers = selected.modifiers
            prefs.currentFocusHotkeyEnabled = enabled
        } else {
            prefs.hotkeyKeyCode = selected.keyCode
            prefs.hotkeyCarbonModifiers = selected.modifiers
            prefs.hotkeyEnabled = enabled
        }
        return true
    }

    @objc private func importProfile() {
        guard !Typist.shared.isTyping else { return }
        typingTest.endSessionForTermination()
        if settings.window?.isVisible == true { settings.commitPendingEdits() }
        if ProfileSharing.importProfile() { settings.refresh() }
    }
    @objc private func exportProfile() {
        guard !Typist.shared.isTyping else { return }
        typingTest.endSessionForTermination()
        if settings.window?.isVisible == true { settings.commitPendingEdits() }
        ProfileSharing.exportProfile()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // windowWillClose doesn't fire during termination, so quitting with the
        // Settings window open would drop in-progress text-field edits.
        if settings.window?.isVisible == true {
            settings.commitPendingEdits()
        }
        typingTest.endSessionForTermination()
    }

    private var isTyping = false

    private func refreshIcon(armed: Bool) {
        statusItem.button?.image = Self.icon(armed: armed, typing: isTyping)
        if !isTyping {
            statusItem.button?.title = armed ? " •" : (lastRunFailed ? " !" : "")
            statusItem.length = armed || lastRunFailed ? NSStatusItem.variableLength : NSStatusItem.squareLength
        }
    }

    // Keep the actual Peck artwork at every state; copy before resizing so the
    // Basic and Advanced header images retain their full native resolution.
    private static func icon(armed: Bool, typing: Bool = false) -> NSImage? {
        let image = NSApp.applicationIconImage.copy() as? NSImage
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = false
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
        menuTarget = TargetApplication.current()
        let menu = NSMenu()
        menu.delegate = self
        func item(_ title: String, _ action: Selector, in targetMenu: NSMenu) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            targetMenu.addItem(entry)
        }
        item(Typist.shared.isTyping ? "Cancel Typing" : "Type at Current Focus", #selector(typeAtCurrentFocus), in: menu)
        item(targeting.isArmed ? "Cancel Targeting" : "Choose a Target…", #selector(toggleTargeting), in: menu)
        menu.addItem(.separator())
        let speed = NSMenuItem(title: "Typing Speed", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu()
        for choice in Preferences.SpeedChoice.allCases {
            let entry = NSMenuItem(title: "\(choice.title) (\(choice.rawValue) ms)", action: #selector(selectMenuSpeed(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = choice.rawValue
            entry.state = Preferences.shared.speedChoice == choice ? .on : .off
            speedMenu.addItem(entry)
        }
        if Preferences.shared.speedChoice == nil {
            let custom = NSMenuItem(title: "Custom: \(Preferences.shared.keystrokeDelayMs) ms", action: nil, keyEquivalent: "")
            custom.isEnabled = false
            speedMenu.addItem(custom)
        }
        speed.submenu = speedMenu
        menu.addItem(speed)
        item("Settings…", #selector(openSettings), in: menu)
        let advanced = NSMenuItem(title: "Advanced", action: nil, keyEquivalent: "")
        let advancedMenu = NSMenu()
        item("Advanced Settings…", #selector(openAdvanced), in: advancedMenu)
        item("Typing Test & Calibration…", #selector(openTypingTest), in: advancedMenu)
        let sendKey = NSMenuItem(title: "Send Key", action: nil, keyEquivalent: "")
        sendKey.submenu = buildSendKeyMenu()
        advancedMenu.addItem(sendKey)
        item("Last Run Status…", #selector(showLastStatus), in: advancedMenu)
        advancedMenu.addItem(.separator())
        item("Import Profile…", #selector(importProfile), in: advancedMenu)
        item("Export Profile…", #selector(exportProfile), in: advancedMenu)
        advanced.submenu = advancedMenu
        menu.addItem(advanced)
        if !AccessibilityGate.check(prompt: false) {
            item("Grant Accessibility Permission…", #selector(openAccessibilitySettings), in: menu)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Peck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        guard let button = statusItem.button else { return }
        statusItem.menu = menu
        button.performClick(nil)
    }

    @objc private func selectMenuSpeed(_ sender: NSMenuItem) {
        guard let choice = Preferences.SpeedChoice(rawValue: sender.tag) else { return }
        applySpeed(choice)
    }
    private func applySpeed(_ choice: Preferences.SpeedChoice) {
        guard !Typist.shared.isTyping else { return }
        typingTest.endSessionForTermination()
        if settings.window?.isVisible == true { settings.commitPendingEdits() }
        Preferences.shared.applySpeed(choice)
        settings.refresh()
        basicSettings.refresh()
    }

    // MARK: - Send Key submenu

    private func buildSendKeyMenu() -> NSMenu {
        let submenu = NSMenu()
        addSpecialKeyItems(SpecialKeyCatalog.primary, to: submenu)
        submenu.addItem(.separator())
        addSpecialKeyItems(SpecialKeyCatalog.interrupts, to: submenu)
        submenu.addItem(.separator())

        let functionKeys = NSMenuItem(title: "Function Keys", action: nil, keyEquivalent: "")
        let functionKeysMenu = NSMenu()
        addSpecialKeyItems(SpecialKeyCatalog.functionKeys, to: functionKeysMenu)
        functionKeys.submenu = functionKeysMenu
        submenu.addItem(functionKeys)

        let arrowKeys = NSMenuItem(title: "Arrow Keys", action: nil, keyEquivalent: "")
        let arrowKeysMenu = NSMenu()
        addSpecialKeyItems(SpecialKeyCatalog.arrowKeys, to: arrowKeysMenu)
        arrowKeys.submenu = arrowKeysMenu
        submenu.addItem(arrowKeys)

        return submenu
    }

    private func addSpecialKeyItems(_ keys: [SpecialKey], to menu: NSMenu) {
        for key in keys {
            let item = NSMenuItem(title: key.title, action: #selector(sendSpecialKeyItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            menu.addItem(item)
        }
    }

    @objc private func sendSpecialKeyItem(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? SpecialKey else { return }
        guard AccessibilityGate.check(prompt: true) else { return }
        targeting.disarm()
        Typist.shared.sendSpecialKey(key, target: menuTarget)

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

    @objc private func typeAtCurrentFocus() {
        targeting.typeAtCurrentFocus(menuTarget)
    }

    @objc private func showLastStatus() {
        guard !Typist.shared.isTyping else { return }
        let alert = NSAlert()
        alert.messageText = "Last Peck Run"
        alert.informativeText = Typist.shared.lastStatus
        alert.runModal()
    }

    @objc private func openTypingTest() {
        guard !Typist.shared.isTyping else { return }
        NSApp.activate(ignoringOtherApps: true)
        typingTest.showWindow(nil)
        typingTest.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        guard !Typist.shared.isTyping else { return }
        typingTest.endSessionForTermination()
        if settings.window?.isVisible == true { settings.window?.close() }
        NSApp.activate(ignoringOtherApps: true)
        basicSettings.showWindow(nil)
        basicSettings.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAdvanced() {
        guard !Typist.shared.isTyping else { return }
        typingTest.endSessionForTermination()
        basicSettings.window?.close()
        NSApp.activate(ignoringOtherApps: true)
        settings.refresh()
        settings.showWindow(nil)
        settings.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibilitySettings() {
        // This is the one affordance guiding the user to the grant the whole app depends
        // on, so don't let it silent-fail. Try the deep link, fall back to the top level
        // of System Settings, and if even that won't open, spell out the manual path.
        let deepLink = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        if NSWorkspace.shared.open(deepLink) { return }

        let topLevel = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        if NSWorkspace.shared.open(topLevel) { return }

        let alert = NSAlert()
        alert.messageText = "Couldn't open System Settings"
        alert.informativeText = "Open System Settings → Privacy & Security → Accessibility "
            + "and enable Peck so it can post keystrokes."
        alert.runModal()
    }
}
