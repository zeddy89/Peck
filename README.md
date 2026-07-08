# Peck

ClickPaste, but for macOS. A menu bar utility that types your clipboard as real keystrokes wherever you click. Built for the places paste goes to die: vSphere web consoles, Proxmox noVNC, RDP sessions, IPMI/iDRAC KVMs, and password fields that block ⌘V.

## How it works

1. Copy something.
2. Click the scope icon in the menu bar (or press ⌃⌥⌘V anywhere).
3. The screen dims with a crosshair. Click your target: a console window, a login prompt, a text field.
4. Peck clicks that spot to focus it, waits a beat, then types your clipboard character by character as synthetic keyboard events.

Press Esc while armed to cancel.

## Building

Open `Peck.xcodeproj` in Xcode (14 or later, macOS 13+ target), select the Peck scheme, and Product → Run. That's it. No dependencies, no packages, no storyboards, no sandbox.

No Xcode installed, or the project file misbehaves? There's a fallback:

```bash
./Scripts/build-no-xcode.sh
```

That produces `build/Peck.app` with plain `swiftc` (needs Command Line Tools). For Intel Macs, change the `-target` triple in the script to `x86_64-apple-macosx13.0`.

## Permissions

Peck posts synthetic mouse and keyboard events, which requires **Accessibility** permission:

System Settings → Privacy & Security → Accessibility → enable Peck.

It will prompt on first launch. Two gotchas worth knowing:

- **Rebuilds can invalidate the grant.** Ad hoc code signatures change on every build, and TCC ties the grant to the signature. If keystrokes silently stop working after a rebuild, remove Peck from the Accessibility list and re-add it, or reset with `tccutil reset Accessibility dev.homelab.peck`. Setting a real development team in Signing & Capabilities makes the signature stable and avoids this entirely.
- **Run it from a stable location.** Move the built app to `/Applications` before granting permission so the path and grant stay consistent.

No sandbox, no network access, no clipboard history, no persistence. It reads the pasteboard once per paste, at the moment you click.

## Settings

Right-click the menu bar icon → Settings.

| Setting | Default | Notes |
|---|---|---|
| Delay before typing | 400 ms | Time between the focus click and the first keystroke. Slow remote consoles need the focus event to round-trip; bump this to 800 to 1000 ms for laggy VPN + noVNC combos. |
| Keystroke delay | 15 ms | Per-character pacing. If a console drops or reorders characters (classic noVNC-over-WAN behavior), raise to 25 to 40 ms. |
| Typing mode | Keycodes | See below. |
| Global hotkey | On | ⌃⌥⌘V toggles targeting from anywhere. |

## Typing modes

**Keycodes (default).** Resolves each character to a real virtual keycode plus modifiers using your *current* keyboard layout (via `UCKeyTranslate`), then presses the actual keys, including physical Shift/Option press-and-release around shifted characters. This is the mode remote consoles want: noVNC and friends key off hardware keycodes and modifier state, not injected text, and will type garbage if you feed them raw Unicode events. Works with QWERTY, Dvorak, AZERTY, whatever the layout is. Characters the layout can't produce (emoji, other scripts) automatically fall back to Unicode injection per character.

**Unicode.** Injects characters directly with `keyboardSetUnicodeString`. Broadest character support, works great in native macOS apps and most browsers, unreliable in VNC-style consoles.

One caveat for the keycode mode: the *guest* VM's keyboard layout matters too. If your Mac is on US QWERTY but the VM console is set to German, symbols will land wrong. That's inherent to how VNC transmits keys, and it's the same behavior ClickPaste has on Windows.

## Notes for the usual suspects

- **Proxmox noVNC / vSphere web console:** keycode mode, keystroke delay 25 ms or higher if characters drop. Great for root passwords into fresh VMs before SSH is up.
- **RDP (Windows App / Microsoft Remote Desktop):** either mode usually works; keycodes is safer for login screens.
- **Password fields that block paste:** they can't block keystrokes. Keycode mode looks exactly like typing because it is.
- **Multi-line pastes:** newlines are sent as Return, tabs as Tab, and CRLF collapses to a single Return. Be careful pasting multi-line text into a shell; each newline executes. That's a feature until it isn't.

## Layout

```
Peck/
├── Peck.xcodeproj/
├── Peck/
│   ├── main.swift                     Entry point, accessory activation policy
│   ├── AppDelegate.swift              Status item, menu, wiring
│   ├── TargetingController.swift      Arm/pick/click/type flow, coordinate flip
│   ├── OverlayWindow.swift            Per-screen crosshair overlay
│   ├── Typist.swift                   Keystroke synthesis, both engines
│   ├── KeyMapper.swift                Layout-aware char → keycode via UCKeyTranslate
│   ├── HotkeyManager.swift            Carbon global hotkey (⌃⌥⌘V)
│   ├── Preferences.swift              UserDefaults-backed settings
│   ├── SettingsWindowController.swift Programmatic settings UI
│   └── AccessibilityGate.swift        AX permission check/prompt
└── Scripts/
    └── build-no-xcode.sh              swiftc fallback build
```

Rename freely: change `PRODUCT_BUNDLE_IDENTIFIER` and the display name in the target's build settings, and update the `tccutil` command above to match.

## Launch at login

System Settings → General → Login Items → add Peck. (Deliberately not automated to keep the app dependency-free and obvious about what it does.)
