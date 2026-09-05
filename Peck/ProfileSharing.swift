import AppKit
import UniformTypeIdentifiers

/// All file actions are initiated through user-selected open/save panels.
enum ProfileSharing {
    static func importProfile() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a Peck settings profile. Files over 16 KB or with unknown fields are rejected."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let profile = try TypingProfile.read(from: url)
            let alert = NSAlert()
            alert.messageText = "Apply \(profile.name ?? "Peck profile")?"
            alert.informativeText = profile.settings.summary
                + "\n\nNotes are user-provided, not proof of remote compatibility:\n"
                + (profile.notes?.isEmpty == false ? profile.notes! : "None")
                + "\n\nHotkeys and launch-at-login are unchanged."
            alert.addButton(withTitle: "Apply Profile")
            alert.addButton(withTitle: "Cancel")
            alert.buttons[0].keyEquivalent = ""
            alert.buttons[1].keyEquivalent = "\r"
            guard alert.runModal() == .alertFirstButtonReturn, !Typist.shared.isTyping else { return false }
            try profile.settings.apply(to: .shared)
            return true
        } catch {
            showError("Could not import profile", error)
            return false
        }
    }

    static func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Peck-profile.json"
        panel.message = "Export current settings only. Do not include passwords or sensitive information in the optional name or notes."
        let name = NSTextField(string: "Peck profile")
        let notes = NSTextField(string: "")
        notes.placeholderString = "Optional notes, provided by you; not a verified compatibility claim"
        let accessory = NSStackView(views: [NSTextField(labelWithString: "Profile name (optional):"), name,
                                           NSTextField(labelWithString: "Notes (optional):"), notes])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 6
        accessory.frame = NSRect(x: 0, y: 0, width: 480, height: 100)
        name.widthAnchor.constraint(equalToConstant: 480).isActive = true
        notes.widthAnchor.constraint(equalToConstant: 480).isActive = true
        panel.accessoryView = accessory
        guard panel.runModal() == .OK, let url = panel.url, !Typist.shared.isTyping else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let profile = try TypingProfile(name: name.stringValue, notes: notes.stringValue,
                                            settings: ProfileSettings(preferences: .shared))
            try profile.encoded().write(to: url, options: .atomic)
        } catch { showError("Could not export profile", error) }
    }

    private static func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        // Decoder debug strings may include attacker-controlled values. Keep
        // arbitrary file contents out of error UI and logs.
        alert.informativeText = (error as? ProfileError)?.localizedDescription
            ?? "The file could not be read or written, or it does not match the supported profile schema. No settings were changed."
        alert.runModal()
    }
}
