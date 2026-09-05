# Historical implementation plan

This records the sequence of development goals. Acceptance criteria below are plans, not verification claims; see [current results](../verification.md).

## Milestone 1: Reliable event delivery

Serialize clipboard typing and special keys, make waits interruptible, and expose focus settling, key hold, and post-Return pacing. An interrupt must finish releasing the current keys before sending its chord. Preflight unsupported keycode characters and warn when the prepared text contains Return, independently of paste size. Preserve clipboard privacy and never retry commands automatically.

Acceptance: meaningful logic tests and application builds pass; cancellation, key release, and timing behavior are exercised where local permissions permit. Remote delivery remains unqualified until received files match the fixture repeatedly.

## Milestone 2: Target settings and visible control

Add manual presets, clear editor-specific indentation choices, a progress display with Cancel, and a local typing-test fixture. Explain that progress measures events sent, not text acknowledged by the guest. Keep test content separate from real passwords or commands. Conservative presets are starting points, not proven compatibility claims.

Acceptance: settings persist and update correctly, the fixture can be sent and compared locally, and warning/cancel/progress flows are usable without showing clipboard content.

## Milestone 3: Verification and distribution

Record an honest compatibility matrix and a repeatable exact-file comparison procedure. Add explicit optional Developer ID signing and notarization packaging; preserve the ad-hoc build path with accurate artifact labels. Release creation failures must never trigger asset replacement.

Acceptance: build/test results are recorded for the current revision; packaging syntax and safe failure paths pass. Developer ID signing and notarization need an available identity and explicit invocation. No signing credentials were available during this work, so Apple-signed distribution is not claimed complete. No commit, tag, release, or publication is part of this implementation run.

## 1.2.1 follow-up: cancellation and target changes

The 1.2.0 tests established scheduling behavior but did not establish safe live input under application switching or Escape in vi. Add ongoing local target checks and consume abort Escape while delivery is active. Check cancellation synchronously, preserve key-up balance, and never emit bracketed-paste cleanup into another target. Stop safely if the required input interception cannot be established. Preserve normal Escape behavior while idle. Offer faster console pacing separately from an optional slower preset; neither is a verified remote fix.

Acceptance: deterministic target-loss and abort-ordering regressions pass, then repeat live scratch-buffer tests. Describe actual process/window identity enforcement precisely; do not claim browser-tab or guest editor focus pinning. Preserve the 1.2.0 results as historical and record 1.2.1 results separately.

## 1.3.0 follow-up: fewer steps and shareable evidence

Add a dedicated current-focus shortcut while retaining crosshair targeting, an explicitly experimental Vim bracketed-paste profile, safe JSON typing-profile import/export, and standard Edit actions for the local test window. Keep hotkeys, credentials, clipboard contents, and machine-specific identity out of exported profiles.

Local speed trials cover 15, 10, 5, and 2 ms, requiring three fresh exact received-text matches for a speed. Never present event counts, stale receiver content, or a local result as remote qualification. Cancellation and closing must restore temporary settings without overwriting independent changes. Keep manual remote test evidence distinct. GLKVM media, network, and clipboard integrations remain research only.

Acceptance: review input validation and profile scope; verify shortcut routing and collisions; test fresh-attempt calibration, mismatches, cancellation, and settings restoration; build/test the current revision. Record actual UI and delivery limits rather than inheriting previous test counts as proof.

## 1.4.0 follow-up: simple everyday settings

Make Basic Settings the primary surface: Fast 2 ms, Medium 5 ms, Slow 15 ms, clear current speed including Custom, and the everyday shortcut. Put detailed timings, profiles, calibration, and confirmation controls in Advanced. Introduce the approved bird identity and native UI informed by the generated design concepts. Preserve the original concept images unchanged and label them separately from actual UI evidence.

Routine paste confirmation is off by default, as explicitly requested. Advanced exposes an opt-in master confirmation switch; strict-keycode failures, missing input protection, Secure Input, cancellation, and target-change stops remain enforced. Do not introduce a generic mandatory warning in place of the removed routine popup.

Acceptance: test master-on/off behavior and migration, verify speed labels reflect actual values, check accessible native Basic/Advanced layouts and old shortcut safety gates, run final builds/tests, and package 1.4.0. The user's successful tests remain user-reported evidence; Fast 2 ms is not universally qualified for remote consoles.
