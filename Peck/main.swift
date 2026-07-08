import AppKit

// Peck — ClickPaste for macOS.
// Menu bar utility: arm the crosshair, click a target, and your clipboard
// is typed there as synthetic keystrokes. Built for VM consoles, noVNC,
// RDP sessions, and paste-hostile password fields.

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon

let delegate = AppDelegate()
app.delegate = delegate
app.run()
