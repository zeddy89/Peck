import XCTest
import Carbon

final class HotkeyManagerTests: XCTestCase {
    private func event(signature: OSType, id: UInt32) throws -> EventRef {
        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event), noErr)
        let result = try XCTUnwrap(event)
        var identifier = EventHotKeyID(signature: signature, id: id)
        XCTAssertEqual(SetEventParameter(result, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        MemoryLayout<EventHotKeyID>.size, &identifier), noErr)
        return result
    }
    func testActualCarbonHandlerDispatchesOnlyMatchingSignatureAndID() throws {
        let crosshair = HotkeyManager(action: .crosshair)
        let focus = HotkeyManager(action: .currentFocus)
        var crosshairCalls = 0
        var focusCalls = 0
        crosshair.onActivate = { crosshairCalls += 1 }
        focus.onActivate = { focusCalls += 1 }
        for (signature, id) in [(HotkeyManager.signature, UInt32(1)), (HotkeyManager.signature, UInt32(2)), (OSType(123), UInt32(1))] {
            let value = try event(signature: signature, id: id)
            defer { ReleaseEvent(value) }
            let crossStatus = crosshair.handle(value)
            let focusStatus = focus.handle(value)
            XCTAssertEqual(crossStatus, signature == HotkeyManager.signature && id == 1 ? noErr : OSStatus(eventNotHandledErr))
            XCTAssertEqual(focusStatus, signature == HotkeyManager.signature && id == 2 ? noErr : OSStatus(eventNotHandledErr))
        }
        XCTAssertEqual(crosshairCalls, 1)
        XCTAssertEqual(focusCalls, 1)
        XCTAssertEqual(focus.handle(nil), OSStatus(eventNotHandledErr))
    }
    func testRejectedReplacementPreservesWorkingBinding() {
        var accepts = true
        var unregistered = 0
        let manager = HotkeyManager(registerEvent: { _, _ in accepts ? OpaquePointer(bitPattern: 1) : nil },
                                    unregisterEvent: { _ in unregistered += 1 })
        let old = HotkeyBinding(keyCode: kVK_ANSI_V, modifiers: controlKey | optionKey | cmdKey)
        XCTAssertTrue(manager.register(old))
        accepts = false
        XCTAssertFalse(manager.register(HotkeyBinding(keyCode: kVK_ANSI_X, modifiers: controlKey | optionKey)))
        XCTAssertEqual(manager.binding, old)
        XCTAssertEqual(unregistered, 0)
        XCTAssertFalse(manager.register(HotkeyBinding(keyCode: -1, modifiers: Int.max)))
        XCTAssertEqual(manager.binding, old)
        manager.unregister()
        XCTAssertEqual(unregistered, 1)
    }
}
