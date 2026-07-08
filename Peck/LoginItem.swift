import ServiceManagement

/// Launch-at-login via `SMAppService.mainApp` (macOS 13+). The registration itself
/// is the source of truth — there is no mirrored UserDefaults flag — so the UI
/// always reflects `status` rather than a stored preference.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success. On failure (e.g. the app isn't in a launchable
    /// location, or the daemon rejects it) the caller should re-read `isEnabled`
    /// and surface the error.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
