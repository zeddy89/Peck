import AppKit
import Carbon

/// Global hotkey via Carbon's RegisterEventHotKey. This API needs no special
/// permissions and works even when Peck is not the active app. The key and
/// modifiers are read from `Preferences`, so the hotkey is user-configurable;
/// call `reregister()` after the user records a new one.
final class HotkeyManager {

    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        // Install the dispatcher handler once. Guarding on handlerRef (in addition
        // to checking the status) prevents a partial-failure path from installing a
        // second handler and leaking the first.
        if handlerRef == nil {
            let callback: EventHandlerUPP = { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onActivate?()
                }
                return noErr
            }

            let installStatus = InstallEventHandler(
                GetEventDispatcherTarget(),
                callback,
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &handlerRef)

            guard installStatus == noErr else {
                handlerRef = nil
                return
            }
        }

        let prefs = Preferences.shared
        let keyCode = UInt32(max(0, prefs.hotkeyKeyCode))
        let modifiers = UInt32(max(0, prefs.hotkeyCarbonModifiers))
        let hotKeyID = EventHotKeyID(signature: OSType(0x5045_434B) /* 'PECK' */, id: 1)

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef)

        if registerStatus != noErr {
            hotKeyRef = nil
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    /// Re-read the hotkey from Preferences and rebind. Call after the user records
    /// a new shortcut.
    func reregister() {
        unregister()
        register()
    }

    deinit {
        unregister()
    }
}
