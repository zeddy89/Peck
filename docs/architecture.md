# Architecture

## Source layout

```
Peck/
├── Peck.xcodeproj/
│   └── xcshareddata/xcschemes/Peck.xcscheme   Shared scheme (build + test)
├── Peck/
│   ├── main.swift                     Entry point, accessory activation policy
│   ├── AppDelegate.swift              Status item, menu, Send Key, wiring, abort routing
│   ├── TargetingController.swift      Arm/pick/click/type flow, clipboard read, confirmation alerts
│   ├── CoordinateMath.swift           Pure Cocoa→CGEvent Y-flip (unit-tested)
│   ├── OverlayWindow.swift            Per-screen crosshair overlay
│   ├── Typist.swift                   Keystroke synthesis, both engines, special keys, cancelable
│   ├── TextProcessing.swift           Line-break/tab classification, control-char filtering, trailing prep
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

Rename freely: change `PRODUCT_BUNDLE_IDENTIFIER` and the display name in the target's build settings, and update the `tccutil` command in [docs/install.md](install.md) to match.

## Design

Peck is deliberately layered: **impure** AppKit/CGEvent shells (`AppDelegate`, `TargetingController`, `Typist`, `OverlayWindow`, `HotkeyManager`, `KeyMonitor`) wrap **pure**, host-lessly unit-tested logic (`TextProcessing`, `CoordinateMath`, `HotkeyFormatter`, `Preferences`, `KeyMapper`).

- The `PeckTests` bundle compiles the pure files directly and runs headless — no app launch, no TCC prompts. New logic should live in the pure layer where it's testable.
- Every synthetic event Peck posts is stamped with a magic `kCGEventSourceUserData` tag so its own events (e.g. the bracketed-paste Escape, or the focus click) can be told apart from a human's — it's a self-identification mechanism, not a trust boundary.
- Typing runs on a serial queue with a per-run generation token for clean cancellation; special keys post on their own queue so they fire immediately. All AppKit work stays on the main thread.

## Continuous integration & releases

- `.github/workflows/ci.yml` builds Debug + Release and runs the tests on every push/PR (pinned to `macos-14`).
- `.github/workflows/release.yml` builds, tests, packages `Peck.app` into a signature-preserving `Peck.zip` (via `ditto`), and publishes it as a GitHub Release asset — triggered by pushing a `v*` tag (or a branch commit marked `[release]`). The tag is derived from `MARKETING_VERSION`.
