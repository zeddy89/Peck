# User guide

## Basic Settings

Right-click Peck's bird icon in the menu bar and open **Settings…**. Basic Settings also appears once after upgrading to this version. Choose **Fast** (2 ms), **Medium** (5 ms), or **Slow** (15 ms). These change only the delay between characters; any Advanced key-hold or Return delay remains in effect. Existing saved timings are preserved. An unmatched delay appears as **Custom** rather than pretending to use a preset. A fresh installation starts at Fast.

Routine paste confirmations are off by default, including multiline and large pastes. Permission, Secure Input, strict-keycode, and target-change failures still stop delivery. You can opt into Return/size confirmations in Advanced. Fast is a timing choice, not proof that a remote console receives every character.

## Advanced settings and presets

Choose **Advanced…** in Basic Settings, or **Advanced > Advanced Settings…** in the status menu. Advanced shares Basic's visual styling and contains detailed timings, typing/indentation mode, profiles, calibration, and confirmation rules. Apply a preset explicitly to change its settings.

| Preset | Mode | Focus delay | Character delay | Key hold | Extra Return delay |
|---|---|---|---|---|---|
| Native editor | Unicode | 400 ms | 2 ms | 0 ms | 0 ms |
| Console (fast, unverified) | Keycodes, strict | 600 ms | 2 ms | 0 ms | 0 ms |
| Vim / vi (paste + Insert mode required) | Keycodes, strict | 600 ms | 2 ms | 0 ms | 0 ms |
| Console (conservative, optional) | Keycodes, strict | 1000 ms | 40 ms | 10 ms | 150 ms |
| Vim bracketed paste (experimental) | Keycodes, strict, bracketed paste | 600 ms | 2 ms | 0 ms | 0 ms |

These are test starting points. The slower option remains available explicitly; it did not establish a fix in the reported tests. Existing saved timings are unchanged until you apply a preset. Neither console preset has been qualified against vSphere or GLKVM by repeated exact-file comparison. The Vim preset does not send `:set paste` or enter Insert mode for you. All presets except experimental Vim bracketed paste turn the indentation workaround off. All set the Return warning rule and trailing-newline stripping, and disable automatic final Return. They preserve the master confirmation setting; an enabled rule remains inactive while the master is off. Custom keeps your current settings.

| Setting | Fresh-install default | Notes |
|---|---|---|
| Delay before typing | 400 ms | Lets the focus click settle before the first key. Increase experimentally if initial characters disappear. |
| Keystroke delay | 2 ms | Wait between characters. This is not a verified safe speed for every console. |
| Key hold | 0 ms | Interval between key-down and key-up, up to 100 ms. |
| Extra Return delay | 0 ms | Additional pause after Return, up to 10,000 ms. |
| Typing mode | Keycodes | Physical keycodes or Unicode injection. |
| Strict keycodes | Off | Refuses a keycode paste containing characters the current layout cannot map, before sending the text. |
| Paste confirmation master | Off | Enables the optional Return/size confirmation rules. |
| Warn on Return rule | On, inactive until master enabled | Confirms whenever the prepared text contains Return, independently of the size rule. |
| Auto-indent workaround | Off | Target-specific. Existing saved choices are preserved. |
| Confirm paste over | 1000 chars, inactive until master enabled | Size rule; `0` disables only this rule. |
| Crosshair hotkey | On, ⌃⌥⌘V | Record a shortcut containing Command, Option, or Control. |
| Current-focus hotkey | On, ⌃⌥V | Uses the existing insertion point without another mouse click. |
| Press Return after typing | Off | Adds Return to the prepared text and participates in the Return warning. |
| Strip trailing newline | On | Removes exactly one trailing newline. Extra trailing blank lines still contain Return. |
| Launch at login | Off | Requires a stable installed location. |

Progress represents text processed and events sent, not acknowledgement that a remote guest received them. Cancel stops pending typing and releases held keys. During active delivery, a human Escape is consumed locally to avoid changing vi's mode; its matching release is consumed too. Other physical keyboard or mouse-button input cancels the run and is passed through. Ordinary Escape is unchanged while idle. Peck refuses to start if its filtering input tap cannot be established. If macOS requests it, enable Input Monitoring as well as Accessibility.

Peck checks the captured local process and window repeatedly, including before key-down, and addresses keyboard events to the captured process. This reduces app-switch spill but does not atomically route to a particular window, browser tab, guest widget, or vi mode. An event already posted cannot be recalled. Target changes or lost Escape protection stop the run without automatically retrying; bracketed-paste cleanup is suppressed after detected target loss. Check the original editor before continuing. **Advanced > Last Run Status…** in the menu and the Typing Test window retain the result without displaying clipboard content. Test with harmless text after changing settings. Never automatically retry a command or password when delivery is uncertain.

## Keeping the insertion point

For editors where another click moves the cursor, first position the insertion point yourself. In vi/Vim, enable paste mode when supported and enter Insert mode. Then press **⌃⌥V**, or right-click Peck and choose **Type at Current Focus…**. Peck captures the local window before the menu and restores that application without another mouse click. It still cannot detect the guest editor's mode. If the captured window cannot be verified, it stops. Current-focus typing uses the same optional confirmation rules as crosshair typing; there is no forced popup. The original ⌃⌥⌘V crosshair shortcut remains separate. Either can be changed or disabled in Settings; an unavailable replacement preserves the previous working binding. A conflicting new default is disabled and reported. Ordinary ⌘V is unchanged.

## Typing modes

Keycodes maps characters using the Mac's active keyboard layout and sends physical modifier events. The guest layout must agree: a US Mac and German guest can produce different punctuation from the same keycodes. With strict mode off, unmappable characters fall back to Unicode injection, which may not work in a remote console. Strict mode preflights the entire prepared text and blocks that fallback.

Unicode injects text directly and is a useful starting point for native Mac editors. It is not a general solution for VNC-style consoles, which may depend on keycodes. When macOS Secure Input is active, Peck refuses to start because it cannot rely on receiving abort Escape. Detecting Secure Input during a run stops delivery. This does not mean every password field enables Secure Input; the restriction follows the detected system state. Close or leave the application enabling it, then retry only after checking the target.

## Auto-indent and vi/Vim

An editor can insert indentation, comment prefixes, or matching brackets as Peck types. Sending the original whitespace afterward can produce an indentation staircase. This is separate from dropped keystrokes.

For vi/Vim, use a scratch file, press Escape, enter `:set paste`, then enter insert mode before targeting the editor. Afterward, press Escape and enter `:set nopaste`. Some vi implementations do not support this option. The Vim preset adjusts Peck only; it cannot configure the guest editor.

- **Off:** sends the prepared text without editor-specific indent handling.
- **Bracketed paste:** sends paste markers for targets that support them. Unsupported targets may display or misinterpret the markers. Test in a scratch buffer; do not assume markers prevent execution in every shell or console.
- **Overwrite indent:** sends Shift-Command-Left after Return to replace automatic indentation in compatible native Mac editors. This is a Mac editing shortcut, not a portable remote-console command. Leave it off for vSphere, GLKVM, and other guest consoles.

### Experimental Vim profile

**Vim bracketed paste (experimental)** sends the existing bracketed-paste markers instead of mode-entry commands. Supported Vim can recognize those markers from Normal or Insert mode, but terminal configuration and editor context matter. Generic vi is not guaranteed to support this. Peck does not probe the guest or automatically send Escape, `:set paste`, or `i`. Qualify this profile in a scratch file before relying on it; no new remote qualification is implied by adding the preset.

## Special keys

Right-click the menu bar icon and choose **Advanced > Send Key** for Ctrl-Alt-Delete, Escape, Ctrl-C, Ctrl-D, Ctrl-Z, function keys, or arrows. The target is captured before the menu opens and rechecked after it closes. Clipboard typing and special keys use the same event queue so modifier events cannot interleave. Interrupt actions cancel current typing before their chord is sent.

## Clipboard and command handling

Newlines become Return, tabs become Tab, and CRLF becomes one Return. A shell may execute every newline. Stripping the final newline does not protect earlier lines or multiple trailing blank lines. Enable the optional Advanced confirmation master and Return rule if you want a prompt before command-bearing newlines.

Peck reads clipboard content plain-text-first and can fall back to RTF when no plain text exists. It does not use the HTML importer or keep a clipboard history. Unsupported control and invisible formatting characters are filtered. The app does not use network services; the separately invoked maintainer notarization script submits a release bundle to Apple.

## Testing

Use the local typing test to check startup characters, punctuation, indentation, and long lines with harmless content. The [compatibility guide](compatibility.md) explains how to save results and compare them exactly. A local success does not establish remote-console compatibility, and screenshots can hide low-contrast punctuation.


## Profiles and calibration

See [profiles and calibration](profiles-and-calibration.md) for portable settings and repeatable speed trials.
