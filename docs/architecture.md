# Architecture

Peck is a native Swift/AppKit menu-bar application targeting macOS 13. It has no third-party runtime dependencies. Platform code handles windows, clipboard access, and input posting; testable logic handles text planning, settings, profiles, and scheduling decisions.

## Main components

| Component | Responsibility |
|---|---|
| `AppDelegate` | Menu-bar item, shortcut routing, window coordination, status |
| `BasicSettingsWindowController` | Exact Fast/Medium/Slow selection, shortcut display, login state |
| `SettingsWindowController` | Advanced timings, modes, optional confirmation rules, profile tools |
| `TargetingController` | Clipboard snapshot, target capture, optional prompt, focus preparation |
| `Typist` | Keyboard mapping, process-addressed event posting, held-key release |
| `DeliveryRunner` / `DeliveryQueue` | Interruptible scheduling, target-loss handling, serialized operations |
| `KeyMonitor` | Filtering event taps, synchronous abort decisions, protection health |
| `TextProcessing` | Newline/control filtering and the final typing plan |
| `HotkeyManager` | Distinct Carbon action identities and transactional rebinding |
| `TypingProfile` / `ProfileSharing` | Bounded portable schema, file panels, import review |
| `Calibration` / `TypingTestWindowController` | One-use trials, ephemeral received text, aggregate results |

## Input flow

Peck reads the clipboard once when submitting a paste. Plain text is preferred; RTF is a fallback, and the HTML importer is not used. The final plan normalizes line breaks and removes unsupported control/format characters. Strict keycode mode rejects unavailable mappings before clicking or posting input.

A captured process/window is checked during preparation and before key-down. Events are addressed to the captured process; held key releases keep that destination. The window check is best-effort and cannot atomically identify a browser tab or guest insertion state. Detected target loss prevents further content and bracketed-paste cleanup.

Typing and special keys share a serial queue. Cancellation stops pending work after bounded waits while finishing key release. A filtering session tap consumes human Escape during delivery and cancels synchronously on physical interaction. Secure Input or unavailable interception prevents starting. Synthetic-event tags distinguish Peck's own input for bookkeeping; they are not a security boundary.

## Settings and evidence

Basic speed changes only character delay. Other values remain Custom. Routine confirmation is opt-in through a master preference, separate from failure checks. Portable profiles include that preference; older profiles without it default to Off. Profiles exclude clipboard data, hotkeys, login registration, and calibration history.

Calibration uses the actual run-start settings snapshot and completion outcome. A local success requires fresh text received through tagged keyboard edits; ordinary paste is not qualifying evidence. Remote receipts are explicitly user-supplied. Neither proves arbitrary console compatibility.

See [build and release](development/build-release.md), [current verification](verification.md), and [historical implementation notes](development/implementation-plan.md).
