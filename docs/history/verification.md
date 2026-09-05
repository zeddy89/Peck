# Historical verification

These records describe earlier revisions. They are not proof for the current release; see [current verification](../verification.md).

| Revision | Final test result | Other recorded checks |
|---|---|---|
| 1.3.0 (6) | 116 passed, zero failures | Release and fallback builds; extracted ad-hoc signature; arm64/x86_64 |
| 1.2.1 (5) | 92 passed, zero failures | Release and fallback builds; extracted ad-hoc signature; arm64/x86_64 |
| 1.2.0 (4) | 81 passed, zero failures | Release and fallback builds; extracted ad-hoc signature; arm64/x86_64 |
| Earlier baseline | 41 passed, zero failures | Debug/clean builds, accessory launch, settings-layout smoke, fallback build |

The 1.3 calibration review corrected stale-configuration qualification paths. Its tests covered fresh completed runs, one-use results, local/manual provenance, mismatch handling, and restoration. Live app access was unavailable for that revision, so no native calibration or profile-dialog success was claimed.

The 1.2.1 investigation followed reports of text reaching another app after switching focus and Escape coinciding with vi text deletion. Event ordering was not captured, and an initial red vi error remained unidentified. Review corrected cleanup that could run after transient target loss. Tests covered filtering decisions and suppression of cleanup after lost protection; they did not post input into another app.

The 1.2.0 review corrected a strict-mode failure when the keyboard mapper was unavailable. Its native settings/test-window inspection showed usable controls but could not establish received keystrokes. A partial GLKVM/nano screenshot looked intact; vi formatting stabilized with paste mode. Earlier apparent missing punctuation was visible after syntax highlighting was disabled. See [compatibility observations](../compatibility.md).

All listed release archives were ad-hoc signed, not notarized. Earlier implementation details and proposed fixes may have changed since the [historical repository review](repository-review.md).
