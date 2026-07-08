import AppKit

/// Watches for Escape while typing is in progress, so a paste can be aborted even
/// though Peck is not the front app and no overlay is up. Uses a global monitor
/// (Esc destined for the target app — this needs Accessibility, which Peck already
/// requires to type) plus a local monitor (when Peck itself is frontmost).
///
/// Peck never synthesizes keycode 53, so its own injected keystrokes cannot trip
/// this monitor.
final class KeyMonitor {

    var onEscape: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let escapeKeyCode: UInt16 = 53

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == self.escapeKeyCode else { return }
            self.onEscape?()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == self.escapeKeyCode else { return event }
            self.onEscape?()
            return nil // swallow so Esc doesn't beep in Peck's own UI
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        stop()
    }
}
