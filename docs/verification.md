# Verification

## Peck 1.4.0

| Check | Result |
|---|---|
| Full XCTest suite | **123 passed, zero failures** |
| Release build | Passed |
| Command Line Tools fallback | Passed |
| Extracted release archive signature | Strict verification passed |
| Release executable | **1.4.0 (7)**, arm64 and x86_64 |
| Signing | Ad-hoc with hardened runtime; not notarized |

SHA-256 of the **locally validated pre-release** `Peck-adhoc.zip`:

```text
a41af9b1927fbdf9a7df58d05dd62c95b6958acdbc9b77686c709d265d05b20e
```

Tests cover scheduling and cancellation, Escape-filter decisions, target-loss cleanup, strict mapping, exact speed selection, saved/custom timing preservation, optional confirmation rules, portable profile validation, hotkey identity/rebinding, and calibration freshness/configuration handling. The build reported an App Intents metadata-skip warning; Peck has no AppIntents dependency.

The release workflow builds a fresh archive, which may have a different hash. Verify a published download against the `SHA256SUMS` asset on its release page; the value above identifies only the local artifact used for the checks recorded here.

## Native UI checks

Basic and Advanced were exercised in dark appearance. Checks confirmed complete speed cards without overlapping labels, matching visual styling and bird headers, Advanced scrolling, and return navigation. The 540-pixel-wide Basic window fit its controls. Fast → Medium → Slow → Fast updated the numeric delay to 2 ms on return. Master confirmation was Off while the dormant Return rule remained On and the size threshold remained 1000.

The calibration window rendered and could be maximized. A harmless multiline sample started without a routine confirmation popup, then stopped because the selected window/modifier startup checks did not become ready. **No received text or calibrated speed was established by that probe.** Automation-generated shortcut input did not exercise physical Carbon shortcut activation. Light appearance was not exercised live.

The generated icon was converted to standard renditions while preserving alpha. Extraction verified all ten standard ICNS renditions. Images under [design](design/README.md) are original concepts, not screenshots of the application.

## Remaining boundaries

- Passing logic tests does not prove actual CGEvent receipt by a browser or remote guest.
- No universal 2 ms remote-console qualification is claimed. User-reported successful vi/Vim tests are useful observations, not a completed compatibility matrix.
- Local process/window checks cannot atomically pin a browser tab, guest widget, or editor mode. Already-posted events cannot be recalled.
- Physical shortcuts, live Escape filtering, and repeated exact received-file comparisons still need target-specific checks.
- Developer ID signing and notarization were not performed.

Use the [compatibility procedure](compatibility.md#test-procedure) for qualification. Earlier results are summarized in [historical verification](history/verification.md).
