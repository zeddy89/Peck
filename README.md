# Peck

ClickPaste, but for macOS. A menu bar utility that types your clipboard as real keystrokes wherever you click. Built for the places paste goes to die: vSphere web consoles, Proxmox noVNC, RDP sessions, IPMI/iDRAC KVMs, and password fields that block ⌘V.

## How it works

1. Copy something.
2. Click the scope icon in the menu bar (or press ⌃⌥⌘V anywhere).
3. The screen dims with a crosshair. Click your target: a console window, a login prompt, a text field.
4. Peck clicks that spot to focus it, waits a beat, then types your clipboard character by character as synthetic keyboard events.

**Aborting.** Press **Esc** while the crosshair is up to cancel before you pick a target. While Peck is *typing*, press **Esc**, press the **global hotkey**, or **click the menu bar icon** to stop immediately — any held modifier is released so nothing sticks down.

## Download & run

Prebuilt releases are on the [Releases page](../../releases). Download `Peck.zip`, unzip it, and drag `Peck.app` to `/Applications`.

The build is **ad-hoc signed and not notarized** (this is a personal/homelab tool, not a Developer-ID-signed release), so Gatekeeper refuses the first launch with *"Peck cannot be opened because the developer cannot be verified."* Clear the download quarantine once:

```bash
xattr -dr com.apple.quarantine /Applications/Peck.app
```

Then open it normally. (Or: System Settings → Privacy & Security → find the blocked-app notice → **Open Anyway**. On recent macOS the old right-click → Open shortcut no longer bypasses this.)

**After updating to a new build you may need to re-grant Accessibility.** An ad-hoc signature changes on every build, and macOS ties the Accessibility grant to the signature, so a fresh download can silently stop posting keystrokes while the toggle still *looks* enabled. If typing stops working after an update, remove Peck from System Settings → Privacy & Security → Accessibility and re-add it, or run `tccutil reset Accessibility dev.homelab.peck`, then relaunch.

## Building

Open `Peck.xcodeproj` in Xcode (15 or later, macOS 13+ target), select the shared **Peck** scheme, and Product → Run. That's it. No dependencies, no packages, no storyboards, no sandbox.

- **Build:** `xcodebuild -project Peck.xcodeproj -scheme Peck -configuration Debug build`
- **Test:** `xcodebuild -project Peck.xcodeproj -scheme Peck test` — the `PeckTests` target is a host-less logic-test bundle covering the coordinate flip, key/newline dispatch, preferences, hotkey formatting, and layout-aware key mapping. It never launches the app, so it runs headless.

No Xcode installed, or the project file misbehaves? There's a fallback:

```bash
./Scripts/build-no-xcode.sh
```

That produces `build/Peck.app` with plain `swiftc` (needs Command Line Tools). It auto-detects your architecture with `uname -m`, so it builds natively on Apple Silicon (arm64) and Intel (x86_64) without editing the triple. If your working copy lives in an iCloud-synced `~/Documents`, the script clears the `com.apple.FinderInfo` xattr and retries `codesign` so the sync layer's re-stamping doesn't break signing.

## Permissions

Peck posts synthetic mouse and keyboard events, which requires **Accessibility** permission:

System Settings → Privacy & Security → Accessibility → enable Peck.

It will prompt on first launch. Three things worth knowing:

- **Rebuilds can invalidate the grant.** Ad hoc code signatures change on every build, and TCC ties the grant to the signature. If keystrokes silently stop working after a rebuild, remove Peck from the Accessibility list and re-add it, or reset with `tccutil reset Accessibility dev.homelab.peck`. Setting a real development team in Signing & Capabilities makes the signature stable and avoids this entirely.
- **Run it from a stable location.** Move the built app to `/Applications` before granting permission so the path and grant stay consistent.
- **Revoking Accessibility mid-session fails silently.** If you turn Peck off in System Settings while it's running, arming still shows the crosshair but no keystrokes land (and the Esc-abort monitor stops seeing keys). Quit and relaunch after re-granting.

No sandbox, no network access, no clipboard history, no persistence. It reads the pasteboard once per paste, at the moment you click.

## Settings

Right-click the menu bar icon → Settings.

| Setting | Default | Notes |
|---|---|---|
| Delay before typing | 400 ms | Time between the focus click and the first keystroke. Slow remote consoles need the focus event to round-trip; bump this to 800–1000 ms for laggy VPN + noVNC combos. |
| Keystroke delay | 15 ms | Per-character pacing. If a console drops or reorders characters (classic noVNC-over-WAN behavior), raise to 25–40 ms. |
| Typing mode | Keycodes | See below. |
| Auto-indent workaround | Off | Defeats a target that auto-indents what Peck types (which stacks indentation on multi-line pastes). See below. |
| Confirm paste over | 1000 chars | Above this many characters, Peck shows the character and line count and asks before typing — the guardrail against pecking a 40 KB file into a root shell. Set to `0` to disable. |
| Global hotkey | On, ⌃⌥⌘V | Toggle it on/off and record a new shortcut. Click the recorder, then press a modifier + key combination (needs at least one of ⌘/⌥/⌃). |
| Press Return after typing | Off | Send one Return once the clipboard has been typed. |
| Strip trailing newline from clipboard | On | Terminal copies almost always drag a trailing newline along, and in a console that newline runs the last command. This drops a single trailing newline before typing. |
| Launch at login | Off | Registers Peck as a login item via `SMAppService`. The checkbox reflects the real registration state. |

**Secure Input.** If another app has *Secure Event Input* enabled when you arm (a password field, the lock screen, some terminals), Peck warns you that keystrokes may be swallowed and lets you proceed anyway.

## Sending special keys

Peck types your clipboard, but a console also needs keys that clipboard text can't carry — **Ctrl-Alt-Del** at a KVM/IPMI login, an interrupt in a shell, a function key in a BIOS menu. Right-click the menu bar icon → **Send Key**:

- **Ctrl-Alt-Delete** — for IPMI/iDRAC KVMs, noVNC, RDP login screens, and Windows. ("Delete" is the PC Delete key, not Backspace.)
- **Escape**, **Ctrl-C** (interrupt), **Ctrl-D** (EOF), **Ctrl-Z** (suspend).
- **Function keys** F1–F12 and the **arrow keys**, in nested submenus.

The key is sent to whatever window has focus — the console you're looking at — right after the menu closes, so there's no crosshair to click. Like typing, it needs the Accessibility grant, and the modifiers are pressed as real keys so VNC/RDP targets register them. (The guest's keyboard layout still applies, the same caveat as keycode typing.)

## Typing modes

**Keycodes (default).** Resolves each character to a real virtual keycode plus modifiers using your *current* keyboard layout (via `UCKeyTranslate`), then presses the actual keys, including physical Shift/Option press-and-release around shifted characters. This is the mode remote consoles want: noVNC and friends key off hardware keycodes and modifier state, not injected text, and will type garbage if you feed them raw Unicode events. Works with QWERTY, Dvorak, AZERTY, whatever the layout is. Characters the layout can't produce (emoji, other scripts) automatically fall back to Unicode injection per character.

**Unicode.** Injects characters directly with `keyboardSetUnicodeString`. Broadest character support, works great in native macOS apps and most browsers, unreliable in VNC-style consoles.

One caveat for the keycode mode: the *guest* VM's keyboard layout matters too. If your Mac is on US QWERTY but the VM console is set to German, symbols will land wrong. That's inherent to how VNC transmits keys, and it's the same behavior ClickPaste has on Windows.

## Auto-indent workaround

Because Peck *types* rather than pastes, targets with auto-indent (vim with `autoindent`, most GUI code editors) re-indent each new line — and Peck then types that line's own leading whitespace on top, so indentation stacks into a staircase. Plain shells (bash/zsh) don't auto-indent, so this only bites in editors.

Two opt-in modes handle it (off by default, since each is target-specific):

- **Bracketed paste — terminals & vim.** Wraps the keystrokes in bracketed-paste markers (`ESC[200~` … `ESC[201~`), which tells vim/readline "this is a paste": no auto-indent, and a multi-line command isn't executed line-by-line — it waits for you to press Return. Needs a target that supports bracketed paste (most modern terminals, shells, and vim do).
- **Overwrite indent — code editors.** After each Return, Peck selects back to the start of the line (⇧⌘←) so the editor's auto-indent is replaced by the text's real indentation. Works best in Cocoa-based editors where ⌘← goes to the true line start.

If a multi-line paste comes out as a staircase, pick the mode matching your target; leave it off for plain shells.

## Notes for the usual suspects

- **Proxmox noVNC / vSphere web console:** keycode mode, keystroke delay 25 ms or higher if characters drop. Great for root passwords into fresh VMs before SSH is up.
- **RDP (Windows App / Microsoft Remote Desktop):** either mode usually works; keycodes is safer for login screens.
- **Password fields that block paste:** they can't block keystrokes. Keycode mode looks exactly like typing because it is.
- **Multi-line pastes:** newlines are sent as Return, tabs as Tab, and CRLF collapses to a single Return. Be careful pasting multi-line text into a shell; each newline executes. Keep "Strip trailing newline" on so the *last* line doesn't auto-run, and leave "Press Return after typing" off unless you want it to.
- **Control characters** other than tabs and newlines (raw ESC, other C0 bytes, DEL, C1 controls) are dropped rather than typed. Invisible Unicode format and bidirectional controls (zero-width spaces/joiners, right-to-left overrides, BOM) are dropped too, so what you see on the clipboard is what gets typed — no hidden characters slip into a console. Escape sequences hidden in copied text can't reach the target, and can't break out of the bracketed-paste wrapper from the inside.
- **Rich text** is handled plain-text-first: if the clipboard has a plain-text flavor, that's what Peck types. Only a clipboard with *no* plain text at all falls back to RTF. Peck never runs the HTML importer on clipboard data — that importer can fetch remote resources while parsing, and Peck makes no network connections, by design.

## Layout

```
Peck/
├── Peck.xcodeproj/
│   └── xcshareddata/xcschemes/Peck.xcscheme   Shared scheme (build + test)
├── Peck/
│   ├── main.swift                     Entry point, accessory activation policy
│   ├── AppDelegate.swift              Status item, menu, wiring, abort routing
│   ├── TargetingController.swift      Arm/pick/click/type flow, confirmation alerts
│   ├── CoordinateMath.swift           Pure Cocoa→CGEvent Y-flip (unit-tested)
│   ├── OverlayWindow.swift            Per-screen crosshair overlay
│   ├── Typist.swift                   Keystroke synthesis, both engines, cancelable
│   ├── TextProcessing.swift           Line-break/tab classification, trailing prep
│   ├── KeyMapper.swift                Layout-aware char → keycode via UCKeyTranslate
│   ├── HotkeyManager.swift            Carbon global hotkey (configurable)
│   ├── HotkeyRecorderView.swift       AppKit shortcut recorder
│   ├── HotkeyFormatter.swift          Pure hotkey → "⌃⌥⌘V" formatting (unit-tested)
│   ├── KeyMonitor.swift               Esc-to-abort monitor (active while typing)
│   ├── LoginItem.swift                Launch-at-login via SMAppService
│   ├── Preferences.swift              UserDefaults-backed settings
│   ├── SettingsWindowController.swift Programmatic settings UI
│   └── AccessibilityGate.swift        AX permission check/prompt
├── PeckTests/                         XCTest logic tests (host-less)
└── Scripts/
    └── build-no-xcode.sh              swiftc fallback build (arch auto-detected)
```

Rename freely: change `PRODUCT_BUNDLE_IDENTIFIER` and the display name in the target's build settings, and update the `tccutil` command above to match.

## Launch at login

Toggle **Launch at login** in Settings. It uses `SMAppService.mainApp` (macOS 13+) with no helper bundle and no third-party dependency. For the registration to stick, run Peck from a stable, signed location (e.g. `/Applications`); an ad hoc build in a temporary directory may be refused by the login-item daemon.
