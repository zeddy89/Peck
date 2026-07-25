# Install & build

## Download & run

Prebuilt releases are on the [Releases page](../../../releases). Download `Peck.zip`, unzip it, and drag `Peck.app` to `/Applications`.

The build is **ad-hoc signed and not notarized** (this is a personal/homelab tool, not a Developer-ID-signed release), so Gatekeeper refuses the first launch with *"Peck cannot be opened because the developer cannot be verified."* Clear the download quarantine once:

```bash
xattr -dr com.apple.quarantine /Applications/Peck.app
```

Then open it normally. (Or: System Settings → Privacy & Security → find the blocked-app notice → **Open Anyway**. On recent macOS the old right-click → Open shortcut no longer bypasses this.)

**After updating to a new build you may need to re-grant Accessibility.** An ad-hoc signature changes on every build, and macOS ties the Accessibility grant to the signature, so a fresh download can silently stop posting keystrokes while the toggle still *looks* enabled. If typing stops working after an update, remove Peck from System Settings → Privacy & Security → Accessibility and re-add it, or run `tccutil reset Accessibility dev.homelab.peck`, then relaunch.

## Permissions

Peck posts synthetic mouse and keyboard events, which requires **Accessibility** permission:

System Settings → Privacy & Security → Accessibility → enable Peck.

It prompts on first launch. Three things worth knowing:

- **Rebuilds can invalidate the grant.** Ad hoc code signatures change on every build, and TCC ties the grant to the signature. If keystrokes silently stop working after a rebuild, remove Peck from the Accessibility list and re-add it, or reset with `tccutil reset Accessibility dev.homelab.peck`. Setting a real development team in Signing & Capabilities makes the signature stable and avoids this entirely.
- **Run it from a stable location.** Move the built app to `/Applications` before granting permission so the path and grant stay consistent.
- **Revoking Accessibility mid-session fails silently.** If you turn Peck off in System Settings while it's running, arming still shows the crosshair but no keystrokes land (and the Esc-abort monitor stops seeing keys). Quit and relaunch after re-granting.

No sandbox, no network access, no clipboard history, no persistence. It reads the pasteboard once per paste, at the moment you click.

## Building from source

Open `Peck.xcodeproj` in Xcode (15 or later, macOS 13+ target), select the shared **Peck** scheme, and Product → Run. That's it. No dependencies, no packages, no storyboards, no sandbox.

- **Build:** `xcodebuild -project Peck.xcodeproj -scheme Peck -configuration Debug build`
- **Test:** `xcodebuild -project Peck.xcodeproj -scheme Peck test` — the `PeckTests` target is a host-less logic-test bundle covering the coordinate flip, key/newline dispatch, preferences, hotkey formatting, and layout-aware key mapping. It never launches the app, so it runs headless.

### No-Xcode fallback

No Xcode installed, or the project file misbehaves?

```bash
./Scripts/build-no-xcode.sh
```

That produces `build/Peck.app` with plain `swiftc` (needs Command Line Tools). It auto-detects your architecture with `uname -m`, so it builds natively on Apple Silicon (arm64) and Intel (x86_64) without editing the triple, and derives the version from the Xcode project so it can't drift. If your working copy lives in an iCloud-synced `~/Documents`, the script clears the `com.apple.FinderInfo` xattr and retries `codesign` so the sync layer's re-stamping doesn't break signing.

## Launch at login

Toggle **Launch at login** in Settings. It uses `SMAppService.mainApp` (macOS 13+) with no helper bundle and no third-party dependency. For the registration to stick, run Peck from a stable, signed location (e.g. `/Applications`); an ad hoc build in a temporary directory may be refused by the login-item daemon.
