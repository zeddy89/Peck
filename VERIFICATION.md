# Verification

What was actually verified for Peck, and what still needs a human because it sits
behind a macOS privacy grant (TCC) or real remote hardware. Written to be honest
about the boundary rather than claim end-to-end success that couldn't be exercised
in this environment.

## Environment

- **Machine:** Apple Silicon (arm64), macOS 26.5.2.
- **Toolchain:** Full **Xcode 26.6** (build 17F113) invoked via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` — the active `xcode-select` directory was Command Line Tools, so all `xcodebuild` commands below were run with that env var. Swift 6.3.3; the project builds in Swift 5 language mode (`SWIFT_VERSION = 5.0`).
- **The project had never been compiled** before this work; it now builds clean.

## Verified programmatically ✅

| Check | Command | Result |
|---|---|---|
| Debug build, zero warnings | `xcodebuild -scheme Peck -configuration Debug build` | `** BUILD SUCCEEDED **`, 0 warnings, 0 errors |
| Clean build (no stale cache) | `xcodebuild clean build` | `** BUILD SUCCEEDED **`, all 15 app sources compiled |
| Unit tests | `xcodebuild -scheme Peck test` | `** TEST SUCCEEDED **`, 41 tests, 0 failures |
| Bundle is menu-bar-only | `PlistBuddy … LSUIElement` | `LSUIElement = true` |
| Ad-hoc signing, hardened runtime off, no sandbox | `codesign -dv --entitlements :-` | `flags=0x2(adhoc)`, no runtime flag, no sandbox entitlement |
| App launches, no Dock icon, no crash | `open Peck.app` + `lsappinfo` + `log show` | Running as `type="UIElement"`, no errors logged |
| Settings UI constructs & lays out | headless harness building `SettingsWindowController` off the real sources + `layoutIfNeeded()` | `SETTINGS_SMOKE_OK` — no NSGridView/Auto-Layout trap, no nil unwrap |
| `swiftc` fallback build | `./Scripts/build-no-xcode.sh` | Produces a valid, ad-hoc-signed `build/Peck.app` (arm64, `codesign --verify` passes) |
| Fallback arch auto-detect | script uses `uname -m` | Builds `arm64` on this host; `x86_64` on Intel without edits |

The **41 unit tests** cover the pure logic that was extracted specifically to be
testable:

- **CoordinateMath** — the Cocoa→CGEvent Y-flip for a point on the primary and on
  displays left / right / above / below it (negative and `> primaryHeight`
  coordinates), plus flip involution.
- **TextProcessing** — `"\r\n"` is one Swift `Character` → exactly one Return; mixed
  CR / CRLF / LF each collapse to one Return; tab dispatch; trailing-newline strip
  (exactly one) and trailing-Return append; `TextNormalizer` normalize / count /
  word-fingerprint.
- **Preferences** — defaults for every key (incl. the new hotkey / threshold /
  trailing options) and persistence across instances, against a throwaway suite.
- **HotkeyFormatter** — `⌃⌥⌘V` rendering, canonical modifier order, key names,
  fallback, and validity rules.
- **KeyMapper** — ASCII round-trips on the current layout (lowercase unshifted,
  uppercase carries Shift and shares a keycode, digit/space coverage ≥ 90% of
  printable ASCII, control chars excluded). Skips gracefully if no layout resolves.

## Adversarial self-review

Two multi-agent review passes (find → adversarially verify) ran over the code.
Confirmed findings were fixed:

- **Overlay teardown / re-entrancy race** (Phase 1) — `picked()` now guards against
  re-entry; `disarm()` severs overlay callbacks, sets `ignoresMouseEvents`, and
  closes the windows so a lingering overlay can neither swallow the synthetic click
  nor trigger a second paste.
- **Overlapping-paste + lost-abort race** (Phase 3) — `Typist` cancellation is now a
  per-run generation token (a second paste can't reset a pending abort; a stale
  abort can't kill a new run), and `arm()` / the menu / the icon all abort typing
  instead of starting an overlapping paste.
- **Single-line rich-only clipboard** returned nil → now falls back to the best rich
  candidate.
- **Menu hotkey label** was hardcoded `⌃⌥⌘V` → now rendered from the live binding.
- **Guardrail alerts** defaulted Return to the destructive action → Cancel is now the
  keyboard default.
- Plus smaller hardening: menu detach deferred off-gesture, nil-button guard,
  HotkeyManager OSStatus checks + failure beep, recorder theme refresh, settings
  reload on reopen.

Review dimensions that came back **clean**: retained cycles / leaks (every stored
closure captures `[weak self]` or a singleton; `KeyMonitor` and `HotkeyManager`
handled correctly) and main-thread discipline (all AppKit/NSEvent/NSAlert/SMAppService
on main; all synthetic typing off-main; `makeMapperIfNeeded`'s `main.sync` is
deadlock-free).

## Requires manual verification 🔶 (TCC-gated — can't be automated here)

Posting synthetic events needs the **Accessibility** grant, and it is tied to the
app's (ad-hoc) code signature. Granting it is an authenticated action in System
Settings that can't be scripted, and screen capture from this agent is likewise
blocked by the **Screen Recording** grant. So the following were **not** exercised
end-to-end here and should be checked by hand after granting Accessibility to a copy
of `Peck.app` in a stable location (e.g. `/Applications`):

1. **Arm via icon → crosshair overlay** appears on every display; **Esc** cancels
   with no system beep; clicking a spot dims-then-types.
2. **Arm via hotkey** (⌃⌥⌘V) from another app.
3. **Multi-line paste into TextEdit** in **both** typing modes (Keycodes and
   Unicode) — verify newlines become Return, tabs become Tab, shifted characters
   are correct.
4. **Abort mid-type** — start a long paste, then press Esc / the hotkey / click the
   icon; typing stops immediately and no modifier is left stuck (test with a paste
   full of capitals/symbols).
5. **Large-paste confirmation** — copy > 1000 chars, arm, pick: the alert shows the
   character and line count; Cancel types nothing, "Type It" proceeds.
6. **Configurable hotkey** — record a new shortcut in Settings; the menu hint and the
   binding update; the old chord stops working and the new one arms.
7. **Trailing options** — "Strip trailing newline" drops the last newline; "Press
   Return after typing" adds one.
7a. **Auto-indent workaround** — paste a multi-line, indented block into an
    auto-indenting target: with the mode off it staircases; "Bracketed paste"
    fixes it in vim/readline (and holds the command until you press Return);
    "Overwrite indent" fixes it in a Cocoa code editor. (The pure plan — marker
    wrapping and select-line-start placement — is unit-tested; the actual
    keystroke effect is AX-gated.)
8. **Secure Input warning** — focus a Secure-Input field (e.g. a password field that
   asserts it) and arm; the warning appears with a proceed option.
9. **Launch at login** — toggle it; confirm via `System Settings → General → Login
   Items` (needs the app in a stable, signed location to register).
10. **TCC edge case** — revoke Accessibility while Peck runs: arming still shows the
    crosshair but keystrokes silently do nothing (and Esc-abort stops seeing keys).
    This is inherent to CGEvent posting; quit and relaunch after re-granting.

Repro for the core path once Accessibility is granted:

```
1. Copy several lines of text (include a tab and a capital letter).
2. Open TextEdit, new document, click into it.
3. Click Peck's menu-bar icon (or press ⌃⌥⌘V).
4. Click inside the TextEdit window.
5. Watch the text type in; confirm newlines/tab/capitals landed correctly.
6. Repeat in Settings → Typing mode → Unicode.
```

## Requires real hardware ⛔ (out of scope for this machine)

The whole point of Peck is remote consoles, which aren't present here:

- **Proxmox noVNC**, **vSphere web console**, **RDP**, **IPMI/iDRAC KVM** — keycode
  delivery to VNC/RDP targets can only be confirmed against an actual console.
  The keycode engine is designed for exactly these (hardware keycodes + physical
  modifier press/release), but "it works in noVNC" is asserted from design, not
  observed here.

## Bottom line

Build, tests, static/adversarial review, headless UI construction, and accessory
launch are **verified**. Actual synthetic-keystroke delivery and the remote-console
behavior are **not** verified in this environment because they require an
Accessibility grant (authenticated) and real remote hardware, respectively. Those
are listed above with exact steps rather than claimed as working.
