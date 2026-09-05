# Installation

## Download and open

Peck requires macOS 13 or later. Download **Peck-adhoc.zip** from the [official releases](https://github.com/zeddy89/Peck/releases/latest), unzip it, and move **Peck.app** to **Applications** before granting permissions. Release builds contain Apple silicon and Intel executables.

The current package is ad-hoc signed with hardened runtime but is **not notarized**. If macOS blocks opening, use **System Settings > Privacy & Security > Open Anyway** when available. For a trusted copy downloaded from this repository, the quarantine attribute can also be removed explicitly:

```bash
xattr -dr com.apple.quarantine /Applications/Peck.app
```

Then open the application. Its bird icon appears in the menu bar; Basic Settings opens on the first launch of this version.

## Permissions

Enable **Peck** in **System Settings > Privacy & Security > Accessibility**. Enable **Input Monitoring** as well if macOS requests it. Peck needs keyboard posting and a filtering event tap so an abort Escape does not reach the receiving editor.

If the tap cannot be established, Peck refuses to type. Detected Secure Input also blocks or stops delivery because Escape interception cannot be relied on in that state. This does not mean every password field is unsupported.

## Updates

Quit the old instance before replacing the app. Keep the installed location stable. An ad-hoc rebuild can require refreshing the permission grant even if its toggle still looks enabled: remove Peck from the Accessibility list, re-add the installed app, and relaunch. If necessary, reset its grant first:

```bash
tccutil reset Accessibility dev.homelab.peck
```

Version 1.4 preserves saved timing values. New installations default to Fast (2 ms); unmatched saved delays display Custom. Routine paste confirmations default to Off, including older saved Return/size rules unless the new master was explicitly enabled. Failure checks remain separate. Old profiles without the master import with it Off.

The current-focus shortcut defaults to **⌃⌥V**, alongside the existing **⌃⌥⌘V** crosshair shortcut. If registration conflicts, choose another shortcut in Advanced; the failure is available in Last Run Status.

## Launch at login

Use **Launch at login** in Basic Settings. The switch reflects macOS registration state. Run Peck from Applications; registration can fail for a temporary or untrusted build.

For source builds and signing, see [build and release](development/build-release.md).
