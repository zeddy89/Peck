import ApplicationServices

/// Synthetic mouse and keyboard events require the Accessibility permission
/// (System Settings → Privacy & Security → Accessibility).
enum AccessibilityGate {
    static func check(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
