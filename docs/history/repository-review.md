# Historical repository review

This is an archived review of an earlier revision. Findings and implementation descriptions below are historical, not the current product contract. See [current verification](../verification.md) and [architecture](../architecture.md).

Reviewed at commit `fe3c41b` ("Settings: apply popup/checkbox changes immediately,
not on window close"). Reviewer read every source file, every test, the project
file, the fallback build script, README, and VERIFICATION.md.

## What the project is

Peck is a macOS menu-bar utility (a ClickPaste port): arm a crosshair, click a
target, and the clipboard is typed there as synthetic CGEvent keystrokes. It is
built for paste-hostile targets — noVNC/vSphere consoles, RDP, IPMI KVMs,
password fields. Swift 5 / AppKit, macOS 13+, no dependencies, no storyboards,
no sandbox (it needs the Accessibility grant to post events).

Architecture is deliberately layered: impure AppKit/CGEvent shells
(`AppDelegate`, `TargetingController`, `Typist`, `OverlayWindow`,
`HotkeyManager`, `KeyMonitor`) around pure, host-lessly unit-tested logic
(`TextProcessing`, `CoordinateMath`, `HotkeyFormatter`, `Preferences`,
`KeyMapper`). 41 XCTest logic tests run headless via a host-less test bundle.

## Current health

**Good.** The code is small (~1.5 kloc app code), idiomatic, and unusually
well-commented about *why* (re-entrancy guards, cancellation generations,
CRLF-as-one-grapheme, TCC caveats). Prior adversarial review passes (see
VERIFICATION.md) already fixed overlay teardown races, overlapping-paste/abort
races, and alert-default hazards. Concurrency discipline is sound: typing runs
on a serial queue with a generation-token cancel; all AppKit work is on main;
`Preferences` is UserDefaults-backed (thread-safe).

The main weaknesses: one real regression introduced by the newest feature
(bracketed paste), a paste-injection gap in that same feature, and zero CI —
nothing runs the test suite automatically, which is exactly how the P0 below
shipped.

## Findings

### P0 — bugs that break a shipped feature

- **P0-1: Bracketed-paste mode aborts itself.** `Typist.execute(.escape)`
  posts a synthetic **keycode 53** key-down/up for the `ESC[200~` / `ESC[201~`
  markers (`Typist.swift:106`). `KeyMonitor` — armed for the whole duration of
  typing — treats **any** keycode-53 keyDown seen by its global/local NSEvent
  monitors as "the user pressed Esc" and cancels the paste
  (`KeyMonitor.swift:21-31`). Its doc comment ("Peck never synthesizes keycode
  53, so its own injected keystrokes cannot trip this monitor") was true until
  commit `d431132` added bracketed paste; it is now false. Net effect: enabling
  the "Bracketed paste" auto-indent workaround cancels the paste at (or shortly
  after) the opening marker. *Fix:* stamp every synthetic event Peck posts with
  a magic `kCGEventSourceUserData` value and have `KeyMonitor` ignore events
  carrying the tag; correct the stale comment.

### P1 — security / correctness / process gaps

- **P1-1 (security): the bracketed-paste guard can be defeated by clipboard
  contents.** Control characters in the clipboard (e.g. a raw `ESC`, or the
  one-byte C1 CSI `U+009B`) are classified as `.literal`, unmappable by
  `KeyMapper` (it filters `< 0x20` and `0x7F`), and therefore **unicode-injected
  verbatim** by `Typist.injectUnicode`. Malicious copied text containing
  `ESC[201~` can close Peck's bracketed-paste wrapper early and smuggle
  keystrokes out of the "don't execute until Return" guard — the classic
  paste-injection attack bracketed paste exists to stop, and the same class of
  attack terminals sanitize on paste. Even outside bracketed-paste mode,
  injecting raw C0/C1 controls into a terminal is never what the user meant by
  "type my clipboard". *Fix:* after line-break normalization, drop C0 controls
  (except tab and the newline set), DEL, and C1 controls from the typing plan.
  Pure `TextProcessing` change; unit-testable.
- **P1-2 (process): no CI.** There is no `.github/workflows/`; `xcodebuild
  test` only runs when someone remembers. The test bundle was explicitly
  designed to run headless on a bare macOS runner (host-less, TCC-free,
  KeyMapper tests skip without a resolvable layout), so a GitHub Actions
  macOS workflow is cheap and high-value. *Fix:* add a workflow running
  `xcodebuild -project Peck.xcodeproj -scheme Peck test` on push/PR.

### P2 — minor bugs, hardening, polish

- **P2-1: The synthetic focus click has `clickState` 0.** `MouseClicker.click`
  never sets `.mouseEventClickState`, so the down/up pair doesn't look like a
  genuine single click; some targets use the click count when deciding focus
  behavior. Real clicks carry `1`. *Fix:* set the field on the down and up
  events. (`TargetingController.swift:168-185`)
- **P2-2: Text-field settings are lost if the user quits with the Settings
  window open.** Numeric fields (delays, threshold) commit only in
  `windowWillClose`, which does not fire when the app terminates.
  *Fix:* commit pending edits from `applicationWillTerminate`.
- **P2-3: The hotkey recorder rejects keypad keys** — `HotkeyFormatter.keyLabels`
  lacks keypad digits, so `isValid` beeps at e.g. ⌃⌥⌘-Keypad-5. Cosmetic;
  **deferred** (label table growth, no behavior risk).
- **P2-4: No LICENSE file.** Public GitHub repo with no license means
  all-rights-reserved by default. Choosing one is the owner's call —
  **flagged, not implemented**.
- **P2-5: `ClipboardTextReader` ranking logic is untested.** The
  plain-vs-rich-flavor preference (multi-line recovery, word-fingerprint match,
  HTML>RTF tie-break) is the subtlest untested logic in the app. It already
  takes an injectable `NSPasteboard`, but exercising it needs a pasteboard
  server, which the host-less test bundle deliberately avoids — **deferred**
  with this note.
- **P2-6 (documented, not fixed): the overwrite-indent chord (⇧⌘←) would
  trigger a user hotkey bound to ⇧⌘←**, since Carbon hotkeys match synthetic
  events, aborting the paste each line. Obscure self-inflicted configuration;
  not worth code.

## Security review (desktop/agent/tray specifics)

- **Attack surface is appropriately tiny.** No network, no persistence beyond
  UserDefaults, no clipboard history, pasteboard read exactly once per pick,
  clipboard contents never logged or displayed (the large-paste alert shows
  counts only — good, the clipboard is often a password).
- **Permissions are minimal and honest**: Accessibility only, prompted via
  `AXIsProcessTrustedWithOptions`; no sandbox exceptions, no input-monitoring
  entitlement games.
- **Existing guardrails are well designed**: large-paste confirmation with
  Cancel as the keyboard default; Secure-Input warning before arming; overlay
  teardown severs callbacks so a synthetic click can't re-trigger a paste of a
  password; abort releases held modifiers.
- **P1-1 above is the one real security finding**: control-character
  injection defeats the bracketed-paste safety wrapper.
- The Carbon hotkey handler, `Unmanaged` userData, and NSEvent monitors are
  lifecycle-correct (owner outlives registration; deinit unregisters).

## Maintainability & test gaps

- The pure/impure split is the repo's best asset; keep new logic (like the
  P1-1 sanitizer) in `TextProcessing` where it's testable.
- `project.pbxproj` is hand-rolled with synthetic IDs; adding *files* means
  manual pbxproj surgery. Prefer extending existing files for small helpers.
- Test gaps: control-character handling (added with P1-1), an assertion that
  `.overwriteIndent` doesn't emit `selectLineStart` after the *appended*
  Return, and `ClipboardTextReader` (deferred, P2-5).
- No CI (P1-2). No CHANGELOG (fine at this size). VERIFICATION.md is an
  unusually honest verification ledger — keep it updated when CI lands.

## IMPLEMENTATION CHECKLIST (Phase 2)

1. **[P0-1]** Tag all Peck-posted synthetic events via `CGEventSource.userData`
   magic; `KeyMonitor` ignores tagged events; fix the stale comment. Files:
   `Typist.swift`, `TargetingController.swift` (MouseClicker), `KeyMonitor.swift`.
2. **[P1-1]** Drop C0 (except tab/newlines), DEL, and C1 control characters in
   `TextProcessing` plan building, so they are never unicode-injected and the
   bracketed-paste wrapper can't be broken from inside. Add unit tests
   (ESC dropped, `U+009B` dropped, tab/newline/é kept, bracketed plan contains
   no `.escape` from content). Update README.
3. **[P1-2]** Add `.github/workflows/ci.yml`: `xcodebuild -project
   Peck.xcodeproj -scheme Peck test` on a macOS runner, push + PR.
4. **[P2-1]** Set `.mouseEventClickState = 1` on the synthetic mouse down/up.
5. **[P2-2]** Commit pending Settings text-field edits in
   `applicationWillTerminate`.
6. Add the missing `typingPlan` test for overwrite-indent + append-Return
   ordering (cheap, rides along with 2).

Deferred: P2-3 (keypad labels), P2-4 (license — owner decision), P2-5
(pasteboard tests need a pasteboard server), P2-6 (documented only).

## Phase 2 status

All six checklist items were implemented (commits `21b09ed`, `7c4deef`,
`8c72de4` and the review-fix commit following them). Both a code-review and an
adversarial security-review pass ran over the diff; both returned PASS. Their
actionable findings were applied: a stronger regression assertion for the
bracketed-paste breakout test, an overwrite-indent sanitization test, an NSLog
when `CGEventSource` creation fails (untagged events would resurrect P0-1),
CI `push` restricted to `main` with `permissions: contents: read` and pinned
`-destination 'platform=macOS'`, and a comment stating the synthetic-event tag
is not a trust boundary.

**Missing infrastructure:** this change was authored on a Linux host with no
Swift toolchain, Xcode, or macOS SDK, so `xcodebuild … test` (the project's
real verify path) could not be executed here. The 48 logic tests (41 existing
+ 7 new test methods) must be run via `xcodebuild -project Peck.xcodeproj
-scheme Peck test` on a Mac — or by the CI workflow added in this change on
first push. The
KeyMonitor/SyntheticEventTag behavior is additionally TCC-gated (needs the
Accessibility grant) and needs the manual bracketed-paste check listed in
VERIFICATION.md §7a.
