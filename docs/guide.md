# User guide

## Settings

Right-click the menu bar icon → Settings.

| Setting | Default | Notes |
|---|---|---|
| Delay before typing | 400 ms | Time between the focus click and the first keystroke. Slow remote consoles need the focus event to round-trip; bump this to 800–1000 ms for laggy VPN + noVNC combos. |
| Keystroke delay | 15 ms | Per-character pacing. If a console drops or reorders characters (classic noVNC-over-WAN behavior), raise to 25–40 ms. |
| Typing mode | Keycodes | See [Typing modes](#typing-modes). |
| Auto-indent workaround | Off | Defeats a target that auto-indents what Peck types (which stacks indentation on multi-line pastes). See [Auto-indent workaround](#auto-indent-workaround). |
| Confirm paste over | 1000 chars | Above this many characters, Peck shows the character and line count and asks before typing — the guardrail against pecking a 40 KB file into a root shell. Set to `0` to disable. |
| Global hotkey | On, ⌃⌥⌘V | Toggle it on/off and record a new shortcut. Click the recorder, then press a modifier + key combination (needs at least one of ⌘/⌥/⌃). |
| Press Return after typing | Off | Send one Return once the clipboard has been typed. |
| Strip trailing newline from clipboard | On | Terminal copies almost always drag a trailing newline along, and in a console that newline runs the last command. This drops a single trailing newline before typing. |
| Launch at login | Off | Registers Peck as a login item via `SMAppService`. The checkbox reflects the real registration state. See [docs/install.md](install.md#launch-at-login). |

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
