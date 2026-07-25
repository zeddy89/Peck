# Peck

**ClickPaste for macOS.** A menu-bar utility that types your clipboard as real keystrokes wherever you click — for the places paste goes to die: vSphere/Proxmox web consoles, RDP, IPMI/iDRAC KVMs, and password fields that block ⌘V.

## How it works

1. Copy something.
2. Click the scope icon in the menu bar (or press ⌃⌥⌘V).
3. The screen dims — click your target.
4. Peck focuses that spot and types your clipboard as synthetic keystrokes.

Press **Esc**, the hotkey, or the menu-bar icon to abort at any point. Need a key typing can't send — **Ctrl-Alt-Del**, a function key, an arrow? The menu bar's **Send Key** submenu does those too.

No network, no sandbox, no clipboard history — it reads the pasteboard once per paste. Posting events needs the macOS **Accessibility** permission (it prompts on first launch).

## Install

Grab `Peck.zip` from the [latest release](../../releases/latest), unzip, and drag `Peck.app` to `/Applications`. It's ad-hoc signed (not notarized), so clear the download quarantine once, then open it and grant Accessibility:

```bash
xattr -dr com.apple.quarantine /Applications/Peck.app
```

Full first-launch details, permissions, and building from source → **[docs/install.md](docs/install.md)**.

## Documentation

| Guide | Covers |
|---|---|
| **[Install & build](docs/install.md)** | Download & first launch, Accessibility, building (Xcode or the `swiftc` fallback), launch at login. |
| **[User guide](docs/guide.md)** | Settings reference, typing modes, Send Key, auto-indent workarounds, and per-target tips (noVNC, RDP, password fields). |
| **[Architecture](docs/architecture.md)** | Source layout and the pure/impure design. |

## Build in one line

```bash
xcodebuild -project Peck.xcodeproj -scheme Peck build
```

macOS 13+, Swift 5, no dependencies. (Or open `Peck.xcodeproj` in Xcode and Run.)
