# Troubleshooting

## Peck refuses to start typing

Open **Advanced > Last Run Status…** for the reason. Check the installed app's [permissions](install.md#permissions), release held modifier keys, and focus the intended window. Secure Input must be inactive for reliable Escape interception. A strict-keycode failure means the selected keyboard layout cannot map the complete prepared text.

If the current-focus shortcut is disabled or unavailable, choose another binding in Advanced. Ordinary Command-V is not Peck's shortcut.

## Indentation or comments accumulate

The editor may insert indentation or comment prefixes while Peck also types the original whitespace. In vi/Vim, press Escape, enter `:set paste` when supported, then enter Insert mode with `i`. `:set paste` alone does not enter Insert mode. After completion, exit Insert mode and restore `:set nopaste` when appropriate.

The experimental Vim bracketed-paste profile is a separate option for supported Vim/terminal combinations. It does not detect the guest or issue mode-entry commands. Do not use the macOS **Overwrite indent** workaround in a remote console.

## Characters are missing or misplaced

Save the received text unchanged and compare it against the original. Turn off word wrap and low-contrast syntax highlighting before interpreting screenshots. Check that local and guest keyboard layouts agree. Test character delay, key hold, and Return delay separately; a slower run succeeding once is not proof of a fix.

Use [calibration](profiles-and-calibration.md#calibration) locally and the [compatibility procedure](compatibility.md#test-procedure) for remote consoles. Do not automatically retry a command whose execution is uncertain.

## Switching apps or pressing Escape

Peck stops on detected local target changes and sends keyboard events to the captured process. It cannot pin a browser tab or guest control atomically. Input already posted may still arrive. Human Escape is consumed during an active run so it does not intentionally change vi's mode; ordinary Escape passes through while idle.

After any interruption, check the original editor before continuing. Failure status does not imply the received file is complete or unchanged.

## Nothing happens after an update

Quit duplicate instances and refresh Accessibility for the actual installed copy. See [update instructions](install.md#updates). The menu-bar app may have no open window; open it again or choose Settings from its bird icon.
