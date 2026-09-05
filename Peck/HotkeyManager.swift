import AppKit
import Carbon

struct HotkeyBinding: Equatable {
    let keyCode: Int
    let modifiers: Int
    var isValid: Bool { HotkeyFormatter.isValid(keyCode: keyCode, carbonModifiers: modifiers) }
}

/// Two registrations share Carbon's dispatcher. Each handler must return
/// eventNotHandledErr for the other registration so only the intended action runs.
final class HotkeyManager {
    enum Action: UInt32 { case crosshair = 1, currentFocus = 2 }
    static let signature: OSType = 0x5045_434B
    var onActivate: (() -> Void)?
    private let action: Action
    private let registerEvent: (HotkeyBinding, EventHotKeyID) -> EventHotKeyRef?
    private let unregisterEvent: (EventHotKeyRef) -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var binding: HotkeyBinding?

    init(action: Action = .crosshair,
         registerEvent: @escaping (HotkeyBinding, EventHotKeyID) -> EventHotKeyRef? = { candidate, identifier in
             var reference: EventHotKeyRef?
             let status = RegisterEventHotKey(UInt32(candidate.keyCode), UInt32(candidate.modifiers),
                 identifier, GetEventDispatcherTarget(), 0, &reference)
             return status == noErr ? reference : nil
         }, unregisterEvent: @escaping (EventHotKeyRef) -> Void = { UnregisterEventHotKey($0) }) {
        self.action = action
        self.registerEvent = registerEvent
        self.unregisterEvent = unregisterEvent
    }

    /// Used directly by the installed Carbon callback and by identity tests.
    func handle(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil,
            &identifier) == noErr,
            identifier.signature == Self.signature, identifier.id == action.rawValue else {
            return OSStatus(eventNotHandledErr)
        }
        onActivate?()
        return noErr
    }

    /// Register a replacement before removing the working old shortcut. Rejected
    /// OS registrations leave the previous binding intact and return false.
    @discardableResult
    func register(_ candidate: HotkeyBinding) -> Bool {
        guard candidate.isValid else { return false }
        if candidate == binding && hotKeyRef != nil { return true }
        if handlerRef == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let callback: EventHandlerUPP = { _, event, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                return Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().handle(event)
            }
            let status = InstallEventHandler(GetEventDispatcherTarget(), callback, 1, &type,
                Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
            guard status == noErr else { handlerRef = nil; return false }
        }
        let identifier = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        guard let replacement = registerEvent(candidate, identifier) else { return false }
        if let hotKeyRef { unregisterEvent(hotKeyRef) }
        hotKeyRef = replacement
        binding = candidate
        return true
    }

    func unregister() {
        if let hotKeyRef { unregisterEvent(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        binding = nil
    }
    deinit { unregister() }
}
